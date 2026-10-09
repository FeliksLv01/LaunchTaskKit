require 'time'
require_relative 'integration'

module MacroDistribution
  module_function

  def config(root)
    JSON.parse(File.read(File.join(root, 'MacroDistribution.json')))
  end

  def preflight(root, release: false)
    data = config(root)
    raise 'Invalid version; use X.Y.Z' unless /\A\d+\.\d+\.\d+\z/.match?(data.fetch('version'))
    %w[Package.resolved Gemfile.lock ThirdPartyNotices/swift-syntax-LICENSE.txt].each do |path|
      raise "Missing #{path}" unless File.file?(File.join(root, path))
    end
    spec = File.read(File.join(root, "#{data.fetch('library')}.podspec"))
    raise 'podspec and distribution version differ' unless spec[/s\.version\s*=\s*'([^']+)'/, 1] == data.fetch('version')
    tracked = MacroBuild.capture('git', '-C', root, 'ls-files', 'Prebuilt', '.lfsconfig')
    raise 'Prebuilt files or LFS endpoint still tracked' if tracked.lines.any? { |path| File.exist?(File.join(root, path.strip)) }
    MacroBuild.capture('bundle', 'check')
    MacroBuild.capture('which', 'xcbeautify')
    if release
      raise 'Release requires a clean committed worktree' unless MacroBuild.capture('git', '-C', root, 'status', '--porcelain').empty?
      MacroBuild.capture('gh', 'auth', 'status', '--hostname', 'github.com')
      origin = MacroBuild.capture('git', '-C', root, 'remote', 'get-url', 'origin').sub(/\.git\z/, '')
      expected = data.fetch('repository')
      raise 'origin does not match configured GitHub repository' unless ["https://github.com/#{expected}", "git@github.com:#{expected}", "ssh://git@github.com/#{expected}"].include?(origin)
    end
    data
  end

  def macro_tests(root, report)
    data = config(root)
    host = File.join(report, 'host-tests')
    FileUtils.mkdir_p(host)
    build = data.fetch('build')
    FileUtils.cp_r(File.join(root, build.fetch('sources')), File.join(host, 'Macros'))
    FileUtils.cp_r(File.join(root, 'Tests', build.fetch('test_target')), File.join(host, 'MacroTests'))
    resolved = JSON.parse(File.read(File.join(root, 'Package.resolved')))
    syntax = resolved.fetch('pins').find { |pin| pin.fetch('identity') == 'swift-syntax' }
    raise 'Missing swift-syntax pin' unless syntax
    File.write(File.join(host, 'Package.swift'), <<~SWIFT)
      // swift-tools-version: 6.0
      import PackageDescription
      import CompilerPluginSupport
      let package = Package(name: "MacroHostTests", dependencies: [
        .package(url: "#{syntax.fetch('location')}", revision: "#{syntax.fetch('state').fetch('revision')}"),
      ], targets: [
        .macro(name: "#{build.fetch('module')}", dependencies: [
          .product(name: "SwiftSyntax", package: "swift-syntax"),
          .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
          .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ], path: "Macros"),
        .testTarget(name: "#{build.fetch('test_target')}", dependencies: [
          "#{build.fetch('module')}", .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        ], path: "MacroTests"),
      ])
    SWIFT
    MacroIntegration.run(['xcrun', 'swift', 'test'], directory: host, log: File.join(report, 'macro-tests.log'))
  end

  def verify(root, hosted: false, remote: false, modes: [:swiftpm, :cocoapods])
    data = preflight(root)
    report = File.join(root, '.distribution', "#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{Process.pid}-#{rand(1_000_000)}")
    FileUtils.mkdir_p(report)
    head, _, head_status = Open3.capture3('git', '-C', root, 'rev-parse', '--verify', 'HEAD')
    summary = { 'status' => 'running', 'source_commit' => head_status.success? ? head.strip : 'uncommitted',
                'dirty' => !MacroBuild.capture('git', '-C', root, 'status', '--porcelain').empty?,
                'environment' => MacroBuild.environment, 'modes' => modes, 'hosted' => hosted, 'remote' => remote }
    begin
      lock, binary = MacroBuild.prepare(root)
      summary['artifact_sha256'] = lock.fetch('sha256')
      raise 'Artifact module differs from configuration' unless lock.fetch('module') == data.fetch('build').fetch('module')
      device = MacroIntegration.simulator
      unless hosted || remote
        MacroIntegration.run(['bundle', 'exec', 'ruby', 'Tests/Distribution/distribution_test.rb'], directory: root, log: File.join(report, 'distribution-tests.log'))
        macro_tests(root, report)
      end
      if remote
        repository = "https://github.com/#{data.fetch('repository')}.git"
        actual = MacroBuild.capture('git', 'ls-remote', repository, "refs/tags/#{data.fetch('version')}").split.first
        raise 'Remote library tag does not match verified commit' unless actual == summary.fetch('source_commit')
        MacroIntegration.test(root, repository: repository, version: data.fetch('version'), modes: modes, report: report, destination: device)
      elsif hosted
        candidate = MacroIntegration.snapshot(root, File.join(report, 'candidate'), lock: lock, version: data.fetch('version'))
        MacroIntegration.test(root, repository: 'file://' + candidate, version: data.fetch('version'), modes: modes, report: report, destination: device)
      else
        MacroIntegration.serve(binary) do |url, requests|
          local_lock = lock.merge('url' => url)
          candidate = MacroIntegration.snapshot(root, File.join(report, 'candidate'), lock: local_lock, version: data.fetch('version'))
          MacroIntegration.test(root, repository: 'file://' + candidate, version: data.fetch('version'), modes: modes, report: report, destination: device) do |mode|
            raise 'SwiftPM unexpectedly downloaded a prebuilt macro' if mode == :swiftpm && !requests.empty?
          end
          if modes.include?(:cocoapods)
            development = File.join(report, 'development library with spaces')
            FileUtils.cp_r(candidate, development)
            MacroArtifact.install(development, cache: File.join(report, 'artifact-cache'))
            MacroIntegration.test(root, repository: 'file://' + candidate, version: data.fetch('version'), modes: [:cocoapods],
                                  report: File.join(report, 'development consumer with spaces'), destination: device, development: development)
            raise 'Development integration repeated artifact download' unless requests.length == 1
          end
          summary['artifact_http_requests'] = requests.length
        end
      end
      summary['status'] = 'passed'
      puts "Verification passed: #{report}"
      report
    rescue StandardError => error
      summary['status'] = 'failed'
      summary['error'] = error.message
      raise
    ensure
      File.write(File.join(report, 'report.json'), JSON.pretty_generate(summary) + "\n")
    end
  end

  def gh(*arguments)
    MacroBuild.capture('gh', *arguments)
  end

  def stage(root, state, name)
    entry = { 'name' => name, 'status' => 'running', 'started_at' => Time.now.utc.iso8601 }
    state.fetch('stages') << entry
    yield
    entry['status'] = 'passed'
  rescue StandardError => error
    entry['status'] = 'failed'
    entry['error'] = error.message
    raise
  ensure
    entry['finished_at'] = Time.now.utc.iso8601
    File.write(File.join(root, '.distribution', state.fetch('report_name')), JSON.pretty_generate(state) + "\n")
  end

  def push(root, ref)
    MacroBuild.capture('git', '-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential', '-C', root, 'push', 'origin', ref)
  end

  def published_releases(repository)
    JSON.parse(gh('api', '--paginate', '--slurp', "repos/#{repository}/releases?per_page=100")).flatten
  end

  def publish_macro(root, data, lock)
    repository = data.fetch('repository')
    tag = lock.fetch('release_tag')
    asset = "#{lock.fetch('module')}-macos-arm64"
    releases = published_releases(repository)
    existing = releases.find { |release| release.fetch('tag_name') == tag }
    if existing
      raise 'Macro release is still a draft' if existing.fetch('draft')
      Dir.mktmpdir('macro-release-check') do |directory|
        gh('release', 'download', tag, '--repo', repository, '--pattern', asset, '--dir', directory)
        raise 'Existing macro release has different bytes; refusing overwrite' unless MacroArtifact.valid?(File.join(directory, asset), lock.fetch('sha256'))
      end
      return
    end
    Dir.mktmpdir('macro-release') do |directory|
      path = File.join(directory, asset)
      FileUtils.cp(File.join(root, 'Prebuilt', lock.fetch('module')), path)
      notes = File.join(directory, 'notes.md')
      File.write(notes, "Macro input: #{lock.fetch('input_fingerprint')}\n\nSHA256: #{lock.fetch('sha256')}\n\nToolchain:\n#{JSON.pretty_generate(lock.fetch('toolchain'))}\n")
      commit = MacroBuild.capture('git', '-C', root, 'rev-parse', 'HEAD')
      gh('release', 'create', tag, path, File.join(root, 'ThirdPartyNotices/swift-syntax-LICENSE.txt'),
         '--repo', repository, '--target', commit, '--title', tag, '--notes-file', notes, '--latest=false')
    end
  end

  def release(root, version, publish_pod: false)
    data = preflight(root, release: true)
    raise 'Requested version differs from configuration' unless data.fetch('version') == version
    lock = MacroArtifact.read_lock(File.join(root, 'MacroArtifact.lock.json'))
    raise 'Artifact inputs changed; run build.sh and commit the resulting lock first' unless lock.fetch('input_fingerprint') == MacroBuild.fingerprint(root, data, MacroBuild.environment)
    commit = MacroBuild.capture('git', '-C', root, 'rev-parse', 'HEAD')
    remote = "https://github.com/#{data.fetch('repository')}.git"
    existing_tag = MacroBuild.capture('git', 'ls-remote', remote, "refs/tags/#{version}").split.first
    raise 'Remote tag already points to another commit' if existing_tag && existing_tag != commit
    local_tag, _, status = Open3.capture3('git', '-C', root, 'rev-parse', '--verify', "refs/tags/#{version}")
    raise 'Local tag already points to another commit' if status.success? && local_tag.strip != commit
    state = { 'version' => version, 'commit' => commit, 'stages' => [],
              'report_name' => "release-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{Process.pid}.json" }
    stage(root, state, 'local-verification') { verify(root) }
    preflight(root, release: true)
    # The source commit must exist remotely before GitHub can tag a macro release.
    stage(root, state, 'source-push') { push(root, 'HEAD') }
    stage(root, state, 'macro-release') { publish_macro(root, data, lock) }
    stage(root, state, 'hosted-verification') { verify(root, hosted: true, modes: [:cocoapods]) }
    stage(root, state, 'library-tag') do
      MacroBuild.capture('git', '-C', root, 'tag', version, commit) unless status.success?
      push(root, "refs/tags/#{version}")
    end
    stage(root, state, 'remote-verification') { verify(root, remote: true) }
    releases = published_releases(data.fetch('repository'))
    unless releases.any? { |release| release.fetch('tag_name') == version }
      notes = File.join(root, '.distribution', 'release-notes.md')
      File.write(notes, "CocoaPods and SwiftPM consumer integration tests passed.\nMacro artifact SHA256: #{lock.fetch('sha256')}\n")
      stage(root, state, 'library-release') { gh('release', 'create', version, '--repo', data.fetch('repository'), '--verify-tag', '--title', version, '--notes-file', notes) }
    end
    if publish_pod
      # Re-run all gates on retry; only an already-published identical spec can be reused.
      stage(root, state, 'pod-publication') do
        MacroIntegration.run(['bundle', 'exec', 'pod', 'trunk', 'push', "#{data.fetch('library')}.podspec", '--allow-warnings'],
                             directory: root, log: File.join(root, '.distribution', 'pod-publish.log'))
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('..', __dir__)
  begin
    Dir.chdir(root) do
      case ARGV.shift
      when 'verify' then MacroDistribution.verify(root)
      when 'release'
        version = ARGV.shift || raise('Usage: release X.Y.Z [--publish-pod]')
        unknown = ARGV - ['--publish-pod']
        raise "Unknown options: #{unknown.join(' ')}" unless unknown.empty?
        FileUtils.mkdir_p(File.join(root, '.distribution'))
        File.open(File.join(root, '.distribution/release.lock'), File::RDWR | File::CREAT, 0o600) do |guard|
          raise 'Another release is running' unless guard.flock(File::LOCK_EX | File::LOCK_NB)
          MacroDistribution.release(root, version, publish_pod: ARGV.include?('--publish-pod'))
        end
      else raise 'Usage: ruby Scripts/distribution.rb verify | release X.Y.Z [--publish-pod]'
      end
    end
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
