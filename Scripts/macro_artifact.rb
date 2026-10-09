require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'uri'
require 'rubygems/version'

module MacroArtifact
  module_function

  def read_lock(path)
    lock = JSON.parse(File.read(path))
    raise 'Unsupported artifact lock schema' unless lock.fetch('schema') == 1
    %w[sha256 input_fingerprint].each do |key|
      raise "Invalid #{key}" unless /\A[0-9a-f]{64}\z/.match?(lock.fetch(key))
    end
    raise 'Invalid macro module' unless /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(lock.fetch('module'))
    raise 'Only macOS arm64 artifacts are supported' unless lock.fetch('architecture') == 'arm64'
    uri = URI(lock.fetch('url'))
    local = %w[127.0.0.1 localhost ::1].include?(uri.host)
    raise 'Artifact URL must use HTTPS (HTTP is allowed only for loopback tests)' unless uri.scheme == 'https' || (uri.scheme == 'http' && local)
    raise 'Invalid minimum macOS version' unless /\A\d+\.\d+(?:\.\d+)?\z/.match?(lock.fetch('minimum_macos'))
    lock
  end

  def valid?(path, sha)
    File.file?(path) && Digest::SHA256.file(path).hexdigest == sha
  end

  def host_arm64?
    /arm64|aarch64/.match?(RbConfig::CONFIG['host_cpu'])
  end

  def install(root, lock_path: File.join(root, 'MacroArtifact.lock.json'), cache: nil)
    raise 'Prebuilt macros require an Apple Silicon host' unless host_arm64?
    lock = read_lock(lock_path)
    host_version, error, status = Open3.capture3('sw_vers', '-productVersion')
    raise error unless status.success?
    raise "Macro requires macOS #{lock.fetch('minimum_macos')} or newer" if Gem::Version.new(host_version.strip) < Gem::Version.new(lock.fetch('minimum_macos'))
    destination = File.join(root, 'Prebuilt', lock.fetch('module'))
    sha = lock.fetch('sha256')
    if valid?(destination, sha)
      File.chmod(0o755, destination)
      return destination
    end
    cache ||= ENV['SWIFT_MACRO_CACHE_DIR'] || File.join(Dir.home, 'Library/Caches/SwiftMacroArtifacts/v1')
    FileUtils.mkdir_p(cache)
    cached = File.join(cache, sha)
    File.open("#{cached}.lock", File::RDWR | File::CREAT, 0o600) do |guard|
      guard.flock(File::LOCK_EX)
      unless valid?(cached, sha)
        temporary = "#{cached}.#{Process.pid}.download"
        begin
          command = ['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '2',
                     '--connect-timeout', '15', '--max-time', '180', '--proto', '=https,http',
                     '--proto-redir', '=https,http', '--output', temporary, lock.fetch('url')]
          _, error, status = Open3.capture3(*command)
          raise "Macro download failed (#{status.exitstatus}): #{error.strip}" unless status.success?
          raise 'Macro artifact SHA256 mismatch' unless valid?(temporary, sha)
          File.chmod(0o755, temporary)
          File.rename(temporary, cached)
        ensure
          FileUtils.rm_f(temporary)
        end
      end
      FileUtils.mkdir_p(File.dirname(destination))
      temporary = "#{destination}.#{Process.pid}.tmp"
      begin
        FileUtils.cp(cached, temporary)
        File.chmod(0o755, temporary)
        File.rename(temporary, destination)
      ensure
        FileUtils.rm_f(temporary)
      end
    end
    destination
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    puts MacroArtifact.install(File.expand_path('..', __dir__))
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
