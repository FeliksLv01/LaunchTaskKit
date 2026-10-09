require 'minitest/autorun'
require 'tmpdir'
require 'socket'
require_relative '../../Scripts/build_macro'

class DistributionTests < Minitest::Test
  def setup
    @temporary = Dir.mktmpdir('macro-cache-tests ')
    @cache = File.join(@temporary, 'cache')
    @bytes = 'executable fixture'
    @requests = 0
    @server = TCPServer.new('127.0.0.1', 0)
    @url = "http://127.0.0.1:#{@server.addr[1]}/macro"
    @thread = Thread.new do
      loop do
        socket = @server.accept
        begin
          socket.gets
          while (line = socket.gets) && line != "\r\n"; end
          @requests += 1
          bytes = @bytes.dup
          socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{bytes.bytesize}\r\nConnection: close\r\n\r\n#{bytes}")
        ensure
          socket.close
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end
  end

  def teardown
    @server.close
    @thread.join
    FileUtils.remove_entry(@temporary)
  end

  def consumer(name, sha: Digest::SHA256.hexdigest(@bytes), url: @url)
    root = File.join(@temporary, name)
    FileUtils.mkdir_p(root)
    lock = { 'schema' => 1, 'module' => 'FixtureMacros', 'architecture' => 'arm64',
             'minimum_macos' => '10.15', 'sha256' => sha, 'input_fingerprint' => 'a' * 64, 'url' => url }
    File.write(File.join(root, 'MacroArtifact.lock.json'), JSON.generate(lock))
    root
  end

  def test_cold_warm_and_cross_version_reuse
    one = consumer('Library 1.0.0')
    first = MacroArtifact.install(one, cache: @cache)
    assert File.executable?(first)
    assert_equal @bytes, File.binread(first)
    MacroArtifact.install(one, cache: @cache)
    MacroArtifact.install(consumer('Library 1.0.1'), cache: @cache)
    assert_equal 1, @requests
  end

  def test_concurrent_consumers_download_once
    roots = 4.times.map { |i| consumer("consumer #{i}") }
    children = roots.map do |root|
      fork do
        MacroArtifact.install(root, cache: @cache)
        exit! 0
      end
    end
    children.each { |pid| assert Process.wait2(pid).last.success? }
    assert_equal 1, @requests
    roots.each { |root| assert File.executable?(File.join(root, 'Prebuilt/FixtureMacros')) }
  end

  def test_corrupt_local_and_shared_cache_are_repaired
    root = consumer('corrupt')
    destination = MacroArtifact.install(root, cache: @cache)
    sha = Digest::SHA256.hexdigest(@bytes)
    File.write(destination, 'corrupt')
    File.write(File.join(@cache, sha), 'corrupt')
    MacroArtifact.install(root, cache: @cache)
    assert_equal @bytes, File.binread(destination)
    assert_equal 2, @requests
  end

  def test_checksum_mismatch_does_not_install_or_poison_cache
    root = consumer('bad checksum', sha: 'b' * 64)
    error = assert_raises(RuntimeError) { MacroArtifact.install(root, cache: @cache) }
    assert_match(/SHA256 mismatch/, error.message)
    refute File.exist?(File.join(root, 'Prebuilt/FixtureMacros'))
    refute File.exist?(File.join(@cache, 'b' * 64))
  end

  def test_unreachable_download_fails_without_artifact
    closed = TCPServer.new('127.0.0.1', 0)
    port = closed.addr[1]
    closed.close
    root = consumer('offline', url: "http://127.0.0.1:#{port}/macro")
    assert_raises(RuntimeError) { MacroArtifact.install(root, cache: @cache) }
    refute File.exist?(File.join(root, 'Prebuilt/FixtureMacros'))
  end

  def test_missing_network_is_not_needed_when_cache_is_warm
    root = consumer('online')
    MacroArtifact.install(root, cache: @cache)
    offline = consumer('offline reuse', url: 'http://127.0.0.1:1/macro')
    assert File.executable?(MacroArtifact.install(offline, cache: @cache))
    assert_equal 1, @requests
  end

  def test_fingerprint_excludes_runtime_tests_and_docs_but_tracks_inputs
    root = File.join(@temporary, 'fingerprint')
    FileUtils.mkdir_p(File.join(root, 'Sources/FixtureMacros'))
    FileUtils.mkdir_p(File.join(root, 'Scripts'))
    %w[Package.swift Package.resolved Scripts/build_macro.rb Sources/FixtureMacros/Macro.swift].each { |path| File.write(File.join(root, path), 'initial') }
    config = { 'build' => { 'sources' => 'Sources/FixtureMacros' } }
    toolchain = { 'swift' => '6.4' }
    original = MacroBuild.fingerprint(root, config, toolchain)
    File.write(File.join(root, 'README.md'), 'new docs')
    File.write(File.join(root, 'Sources/Runtime.swift'), 'new UI')
    assert_equal original, MacroBuild.fingerprint(root, config, toolchain)
    refute_equal original, MacroBuild.fingerprint(root, config, { 'swift' => '6.5' })
    File.write(File.join(root, 'Sources/FixtureMacros/Macro.swift'), 'changed macro')
    refute_equal original, MacroBuild.fingerprint(root, config, toolchain)
  end
end

require_relative 'release_test'
