require_relative 'macro_artifact'

module MacroBuild
  module_function

  def capture(*command)
    output, error, status = Open3.capture3(*command)
    raise "Command failed: #{command.join(' ')}\n#{error}" unless status.success?
    output.strip
  end

  def environment
    developer = capture('xcode-select', '-p')
    plist = File.expand_path('../Info.plist', developer)
    {
      'swift' => capture('xcrun', 'swift', '--version'),
      'xcode_build' => capture('/usr/libexec/PlistBuddy', '-c', 'Print :DTXcodeBuild', plist),
      'macos_sdk' => capture('xcrun', '--sdk', 'macosx', '--show-sdk-version'),
      'host_macos' => capture('sw_vers', '-productVersion')
    }
  end

  def fingerprint(root, config, toolchain)
    files = ['Package.swift', 'Package.resolved', 'Scripts/build_macro.rb'] +
            Dir.glob(File.join(root, config.fetch('build').fetch('sources'), '**', '*')).select { |p| File.file?(p) }.map { |p| p.delete_prefix("#{root}/") }
    digest = Digest::SHA256.new
    digest << JSON.generate(config.fetch('build')) << JSON.generate(toolchain)
    files.sort.each { |path| digest << path << "\0" << File.binread(File.join(root, path)) << "\0" }
    digest.hexdigest
  end

  def prepare(root, force: false)
    raise 'Macro builds require Apple Silicon' unless MacroArtifact.host_arm64?
    config = JSON.parse(File.read(File.join(root, 'MacroDistribution.json')))
    build = config.fetch('build')
    toolchain = environment
    input = fingerprint(root, config, toolchain)
    lock_path = File.join(root, 'MacroArtifact.lock.json')
    if !force && File.file?(lock_path)
      lock = MacroArtifact.read_lock(lock_path)
      if lock['input_fingerprint'] == input
        destination = MacroArtifact.install(root)
        puts "Reusing #{build.fetch('module')} (#{input})"
        return [lock, destination]
      end
    end
    module_name = build.fetch('module')
    command = ['xcrun', 'swift', 'build', '--configuration', build.fetch('configuration'),
               '--target', build.fetch('test_target'), '--arch', build.fetch('architecture'),
               '--scratch-path', File.join(root, '.build/macro'), '--force-resolved-versions']
    build.fetch('swift_flags').each { |flag| command += ['-Xswiftc', flag] }
    Dir.chdir(root) do
      raise 'Macro build failed' unless system(*command)
      output = capture(*(command + ['--show-bin-path']))
      candidates = ["#{module_name}-tool", module_name].map { |name| File.join(output, name) }.select { |path| File.file?(path) }
      raise "Expected one macro executable, found #{candidates.length}" unless candidates.length == 1
      destination = File.join(root, 'Prebuilt', module_name)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(candidates.first, destination)
      capture('strip', destination)
      File.chmod(0o755, destination)
      raise 'Expected an arm64 executable' unless capture('lipo', '-archs', destination) == 'arm64'
      libraries = capture('otool', '-L', destination)
      raise 'Macro links a non-portable library' if libraries.lines.drop(1).any? { |line| !line.strip.start_with?('/usr/lib/', '/System/Library/', '@rpath/libswift') }
      minimum = capture('xcrun', 'vtool', '-show-build', destination)[/minos\s+(\S+)/, 1]
      raise 'Cannot determine minimum macOS version' unless minimum
      sha = Digest::SHA256.file(destination).hexdigest
      release_tag = "macro-#{module_name}-#{input}"
      lock = { 'schema' => 1, 'module' => module_name, 'architecture' => 'arm64',
               'minimum_macos' => minimum, 'input_fingerprint' => input, 'sha256' => sha,
               'url' => "https://github.com/#{config.fetch('repository')}/releases/download/#{release_tag}/#{module_name}-macos-arm64",
               'release_tag' => release_tag, 'toolchain' => toolchain, 'linked_libraries' => libraries.lines.drop(1).map(&:strip) }
      File.write(lock_path, JSON.pretty_generate(lock) + "\n")
      cache = ENV['SWIFT_MACRO_CACHE_DIR'] || File.join(Dir.home, 'Library/Caches/SwiftMacroArtifacts/v1')
      FileUtils.mkdir_p(cache)
      File.open(File.join(cache, "#{sha}.lock"), File::RDWR | File::CREAT, 0o600) do |guard|
        guard.flock(File::LOCK_EX)
        temporary = File.join(cache, "#{sha}.#{Process.pid}.tmp")
        FileUtils.cp(destination, temporary)
        File.rename(temporary, File.join(cache, sha))
      end
      puts "Built #{module_name} (#{input})"
      [lock, destination]
    end
  end
end

MacroBuild.prepare(File.expand_path('..', __dir__), force: ARGV.include?('--force')) if $PROGRAM_NAME == __FILE__
