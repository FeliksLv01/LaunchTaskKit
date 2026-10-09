require 'xcodeproj'
require 'shellwords'
require 'tmpdir'
require 'socket'
require_relative 'build_macro'

module MacroIntegration
  module_function

  def run(command, directory:, log:, environment: {})
    FileUtils.mkdir_p(File.dirname(log))
    # Bash pipefail keeps xcodebuild/tee failures visible; xcbeautify is mandatory.
    pipeline = command.shelljoin + ' 2>&1 | tee ' + log.shellescape
    pipeline += ' | xcbeautify' if command.first == 'xcodebuild'
    puts "Running #{command.first} (log: #{log})"
    success = system(environment, '/bin/bash', '-o', 'pipefail', '-c', pipeline, chdir: directory)
    raise "Failed: #{command.first}; see #{log}" unless success
  end

  def simulator
    devices = JSON.parse(MacroBuild.capture('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))
    candidates = devices.fetch('devices').select { |runtime, _| runtime.include?('iOS') }.values.flatten
    device = candidates.find { |d| d['state'] == 'Booted' } || candidates.first
    raise 'No available iOS Simulator; install a runtime in Xcode first' unless device
    unless device['state'] == 'Booted'
      MacroBuild.capture('xcrun', 'simctl', 'boot', device.fetch('udid'))
    end
    MacroBuild.capture('xcrun', 'simctl', 'bootstatus', device.fetch('udid'), '-b')
    device.fetch('udid')
  end

  def serve(binary)
    server = TCPServer.new('127.0.0.1', 0)
    url = "http://127.0.0.1:#{server.addr[1]}/macro"
    requests = []
    thread = Thread.new do
      loop do
        socket = server.accept
        begin
          line = socket.gets
          while (header = socket.gets) && header != "\r\n"; end
          requests << line
          payload = File.binread(binary)
          socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{payload.bytesize}\r\nConnection: close\r\n\r\n")
          socket.write(payload)
        ensure
          socket.close
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end
    yield url, requests
  ensure
    server&.close
    thread&.join
  end

  def snapshot(root, destination, lock:, version:)
    FileUtils.mkdir_p(destination)
    list = MacroBuild.capture('git', '-C', root, 'ls-files', '--cached', '--others', '--exclude-standard').lines.map(&:chomp).uniq
    list.each do |relative|
      next if relative.start_with?('Prebuilt/', '.distribution/', '.build/')
      source = File.join(root, relative)
      next unless File.file?(source)
      path = File.join(destination, relative)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(source, path)
    end
    File.write(File.join(destination, 'MacroArtifact.lock.json'), JSON.pretty_generate(lock) + "\n")
    spec_path = Dir.glob(File.join(destination, '*.podspec')).fetch(0)
    spec = File.read(spec_path).sub(/s\.version\s*=\s*'[^']*'/, "s.version = '#{version}'")
    File.write(spec_path, spec)
    MacroBuild.capture('git', '-C', destination, 'init', '-q')
    MacroBuild.capture('git', '-C', destination, 'add', '.')
    MacroBuild.capture('git', '-C', destination, '-c', 'user.name=Macro Verification', '-c', 'user.email=macro-verification@localhost', 'commit', '-qm', 'Candidate integration fixture')
    MacroBuild.capture('git', '-C', destination, 'tag', version)
    destination
  end

  def configure(target, config)
    target.build_configurations.each do |build|
      build.build_settings.merge!(
        'SWIFT_VERSION' => '6.0', 'IPHONEOS_DEPLOYMENT_TARGET' => config.fetch('ios_deployment_target'),
        'GENERATE_INFOPLIST_FILE' => 'YES', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES', 'CODE_SIGNING_ALLOWED' => 'NO',
        'PRODUCT_BUNDLE_IDENTIFIER' => "local.macro.#{target.name}",
        'TARGETED_DEVICE_FAMILY' => '1,2', 'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
        'OTHER_SWIFT_FLAGS' => ['$(inherited)'] + config.fetch('consumer_swift_flags'),
        'ENABLE_TESTABILITY' => 'YES', 'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator'
      )
    end
  end

  def add_source(project, target, name, source, directory)
    path = File.join(directory, name)
    File.write(path, source)
    reference = project.main_group.new_file(name)
    target.source_build_phase.add_file_reference(reference)
  end

  def package_dependency(project, target, package)
    dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dependency.package = package
    dependency.product_name = 'PLACEHOLDER'
    target.package_product_dependencies << dependency
    reference = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    reference.product_ref = dependency
    target.frameworks_build_phase.files << reference
    dependency
  end

  def fixture(root, directory, config, repository, version, mode, development: nil)
    FileUtils.mkdir_p(directory)
    project = Xcodeproj::Project.new(File.join(directory, 'MacroConsumer.xcodeproj'))
    app = project.new_target(:application, 'MacroConsumer', :ios, config.fetch('ios_deployment_target'))
    tests = project.new_target(:unit_test_bundle, 'MacroConsumerTests', :ios, config.fetch('ios_deployment_target'))
    [app, tests].each { |target| configure(target, config) }
    tests.add_dependency(app)
    tests.build_configurations.each do |build|
      build.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/MacroConsumer.app/MacroConsumer'
      build.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    end
    add_source(project, app, 'App.swift', "import SwiftUI\n@main struct ConsumerApp: App { var body: some Scene { WindowGroup { Text(\"Macro integration\") } } }\n", directory)
    probe = File.read(File.join(root, 'Tests/Integration/Probe.swift'))
    if mode == :swiftpm
      package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
      package.repositoryURL = repository
      package.requirement = { 'kind' => 'exactVersion', 'version' => version }
      project.root_object.package_references << package
      [app, tests].each do |target|
        dependency = package_dependency(project, target, package)
        dependency.product_name = config.fetch('library')
      end
    end
    test_source = "import XCTest\nimport #{config.fetch('library')}\n"
    if mode == :cocoapods
      %w[DirectConsumer TransitiveConsumer].each do |name|
        pod_root = File.join(directory, name)
        FileUtils.mkdir_p(pod_root)
        source = probe.gsub('PROBE_NAME', name + 'Probe').gsub('PROBE_ID', name)
        source = "import DirectConsumer\n" + source if name == 'TransitiveConsumer'
        File.write(File.join(pod_root, 'Probe.swift'), source)
        dependencies = name == 'DirectConsumer' ? "s.dependency '#{config.fetch('library')}', '#{version}'" : "s.dependency 'DirectConsumer'"
        File.write(File.join(pod_root, "#{name}.podspec"), <<~SPEC)
          Pod::Spec.new do |s|
            s.name = '#{name}'
            s.version = '1.0.0'
            s.summary = 'Integration fixture'
            s.homepage = 'https://example.com'
            s.license = { :type => 'MIT', :text => 'Integration fixture' }
            s.author = 'Macro verification'
            s.source = { :git => '#{repository}', :tag => '#{version}' }
            s.ios.deployment_target = '#{config.fetch('ios_deployment_target')}'
            s.swift_version = '6.0'
            s.source_files = '*.swift'
            #{dependencies}
          end
        SPEC
        test_source += "import #{name}\n"
      end
      test_source += "\n" + probe.gsub('PROBE_NAME', 'ApplicationProbe').gsub('PROBE_ID', 'application')
      test_source += "\nfinal class MacroIntegrationTests: XCTestCase {\n @MainActor func testMacroExpansionAndRegistration() {\n XCTAssertTrue(ApplicationProbeCheck())\n XCTAssertTrue(DirectConsumerProbeCheck())\n XCTAssertTrue(TransitiveConsumerProbeCheck())\n }\n}\n"
      hook = File.join(root, 'Scripts', 'consumer_macro_flags.rb')
      FileUtils.cp(hook, File.join(directory, 'consumer_macro_flags.rb'))
      source_line = development ? "pod '#{config.fetch('library')}', :path => #{development.inspect}" : "pod '#{config.fetch('library')}', :git => '#{repository}', :tag => '#{version}'"
      File.write(File.join(directory, 'Podfile'), <<~PODFILE)
        platform :ios, '#{config.fetch('ios_deployment_target')}'
        install! 'cocoapods', :deterministic_uuids => true
        use_frameworks! :linkage => :static
        require_relative 'consumer_macro_flags'
        target 'MacroConsumer' do
          #{source_line}
          pod 'DirectConsumer', :path => 'DirectConsumer'
          pod 'TransitiveConsumer', :path => 'TransitiveConsumer'
          target 'MacroConsumerTests' do
            inherit! :complete
          end
        end
        post_install do |installer|
          inject_macro_flags(installer, '#{config.fetch('library')}', '#{config.fetch('build').fetch('module')}', #{config.fetch('consumer_swift_flags').inspect})
          inject_macro_flags(installer, '#{config.fetch('library')}', '#{config.fetch('build').fetch('module')}', #{config.fetch('consumer_swift_flags').inspect})
        end
      PODFILE
    else
      test_source += "\n" + probe.gsub('PROBE_NAME', 'ApplicationProbe').gsub('PROBE_ID', 'application')
      test_source += "\nfinal class MacroIntegrationTests: XCTestCase {\n @MainActor func testMacroExpansionAndRegistration() { XCTAssertTrue(ApplicationProbeCheck()) }\n}\n"
    end
    add_source(project, tests, 'IntegrationTests.swift', test_source, directory)
    if mode == :swiftpm
      Dir.glob(File.join(root, 'Tests', config.fetch('library') + 'Tests', '*.swift')).each_with_index do |path, index|
        add_source(project, tests, "LibraryTests#{index}.swift", File.read(path), directory)
      end
    end
    scheme = Xcodeproj::XCScheme.new
    scheme.add_build_target(app)
    scheme.add_test_target(tests)
    scheme.set_launch_target(app)
    project.save
    scheme.save_as(project.path, 'MacroConsumer', true)
  end

  def test(root, repository:, version:, modes: [:swiftpm, :cocoapods], report:, destination:, development: nil)
    config = JSON.parse(File.read(File.join(root, 'MacroDistribution.json')))
    FileUtils.mkdir_p(report)
    modes.each do |mode|
      directory = File.join(report, mode.to_s)
      fixture(root, directory, config, repository, version, mode, development: development)
      environment = { 'SWIFT_MACRO_CACHE_DIR' => File.join(report, 'artifact-cache'), 'BUNDLE_GEMFILE' => File.join(root, 'Gemfile'),
                      'CP_HOME_DIR' => File.join(report, 'cocoapods-home'), 'CP_CACHE_DIR' => File.join(report, 'cocoapods-cache') }
      if mode == :cocoapods
        run(['bundle', 'exec', 'pod', 'install'], directory: directory, log: File.join(report, 'pod-install.log'), environment: environment)
        installed_root = development || File.join(directory, 'Pods', config.fetch('library'))
        raise 'Macro was not materialized' unless File.executable?(File.join(installed_root, 'Prebuilt', config.fetch('build').fetch('module')))
        pod_project = Xcodeproj::Project.open(File.join(directory, 'Pods/Pods.xcodeproj'))
        %w[DirectConsumer TransitiveConsumer].each do |name|
          target = pod_project.targets.find { |item| item.name == name } || raise("Missing #{name}")
          target.build_configurations.each do |build|
            flags = build.build_settings['OTHER_SWIFT_FLAGS'].to_s
            raise 'Macro flag injection is not idempotent' unless flags.scan('-load-plugin-executable').length == 1
          end
        end
      end
      command = ['xcodebuild', mode == :cocoapods ? '-workspace' : '-project', mode == :cocoapods ? 'MacroConsumer.xcworkspace' : 'MacroConsumer.xcodeproj',
                 '-scheme', 'MacroConsumer', '-destination', "platform=iOS Simulator,id=#{destination}",
                 '-derivedDataPath', File.join(directory, 'DerivedData'), '-clonedSourcePackagesDirPath', File.join(directory, 'SourcePackages'),
                 '-resultBundlePath', File.join(directory, 'Tests.xcresult'), '-parallel-testing-enabled', 'NO', '-skipMacroValidation', 'test', 'CODE_SIGNING_ALLOWED=NO']
      run(command, directory: directory, log: File.join(report, "#{mode}.log"), environment: environment)
      yield mode if block_given?
    end
  end
end
