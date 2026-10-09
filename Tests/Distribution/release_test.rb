require_relative '../../Scripts/distribution'

class ReleaseGateTests < Minitest::Test
  def with_release(failure: nil)
    Dir.mktmpdir('release-gates') do |root|
      FileUtils.mkdir_p(File.join(root, '.distribution'))
      events = []
      data = { 'version' => '1.0.0', 'repository' => 'owner/Library', 'library' => 'Library' }
      lock = { 'input_fingerprint' => 'input', 'sha256' => 'sha' }
      capture = lambda do |*command|
        if command.include?('push') || command.include?('tag')
          events << command
          ''
        elsif command.include?('ls-remote')
          ''
        else
          'commit'
        end
      end
      verifier = lambda do |*_, **options|
        phase = options[:remote] ? :remote : options[:hosted] ? :hosted : :local
        events << phase
        raise 'Gate failed' if phase == failure
      end
      status = Struct.new(:success?).new(false)
      MacroDistribution.stub(:preflight, ->(*_, **_) { data }) do
        MacroArtifact.stub(:read_lock, lock) do
          MacroBuild.stub(:environment, {}) do
            MacroBuild.stub(:fingerprint, 'input') do
              MacroBuild.stub(:capture, capture) do
                Open3.stub(:capture3, ['', '', status]) do
                  MacroDistribution.stub(:verify, verifier) do
                    MacroDistribution.stub(:publish_macro, ->(*_) { events << :macro }) do
                      MacroDistribution.stub(:gh, ->(*args) { events << args; '[]' }) do
                        yield root, events
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def test_local_failure_never_pushes_or_publishes
    with_release(failure: :local) do |root, events|
      assert_raises(RuntimeError) { MacroDistribution.release(root, '1.0.0') }
      assert_equal [:local], events
    end
  end

  def test_hosted_failure_never_tags_library
    with_release(failure: :hosted) do |root, events|
      assert_raises(RuntimeError) { MacroDistribution.release(root, '1.0.0') }
      assert_includes events, :macro
      refute events.any? { |event| event.is_a?(Array) && event.include?('tag') }
      refute events.any? { |event| event.is_a?(Array) && event.first == 'release' }
    end
  end

  def test_remote_failure_never_creates_library_release
    with_release(failure: :remote) do |root, events|
      assert_raises(RuntimeError) { MacroDistribution.release(root, '1.0.0') }
      assert_includes events, :remote
      refute events.any? { |event| event.is_a?(Array) && event.first == 'release' }
    end
  end

  def test_success_runs_every_gate_before_library_release
    with_release do |root, events|
      MacroDistribution.release(root, '1.0.0')
      assert_equal [:local, :macro, :hosted, :remote], events.select { |event| event.is_a?(Symbol) }
      creation = events.find_index { |event| event.is_a?(Array) && event[0, 2] == ['release', 'create'] }
      assert creation
      assert_operator events.index(:remote), :<, creation
    end
  end
end
