require 'set'
require 'shellwords'

def inject_macro_flags(installer, library, macro_module, extra_flags = [])
  development = installer.sandbox.development_pods[library]&.expand_path
  development = development.dirname if development&.file?
  root = development ? development.to_s : "${PODS_ROOT}/#{library}"
  plugin = "#{root}/Prebuilt/#{macro_module}##{macro_module}"
  quoted = '"' + plugin.gsub('"', '\\"') + '"'
  flags = "-load-plugin-executable #{quoted} #{extra_flags.shelljoin}".strip
  projects = [installer.pods_project]
  projects.concat(installer.generated_projects) if installer.respond_to?(:generated_projects)
  projects = projects.compact.uniq
  targets = projects.flat_map(&:targets)
  map = targets.to_h { |target| [target.name, target] }
  depends = lambda do |target, seen|
    next false unless seen.add?(target.name)
    target.dependencies.any? do |dependency|
      name = dependency.name || dependency.target&.name
      name == library || ((other = dependency.target || map[name]) && depends.call(other, seen))
    end
  end
  targets.each do |target|
    next if target.name.start_with?('Pods-') || (target.name != library && !depends.call(target, Set.new))
    target.build_configurations.each do |configuration|
      current = configuration.build_settings['OTHER_SWIFT_FLAGS'] || '$(inherited)'
      current = current.join(' ') if current.is_a?(Array)
      next if current.include?("##{macro_module}")
      configuration.build_settings['OTHER_SWIFT_FLAGS'] = "#{current} #{flags}"
    end
  end
  return unless development
  installer.aggregate_targets.each do |aggregate|
    aggregate.xcconfigs.each do |name, xcconfig|
      value = xcconfig.attributes['OTHER_SWIFT_FLAGS']
      next unless value&.include?("${PODS_ROOT}/#{library}/Prebuilt/")
      xcconfig.attributes['OTHER_SWIFT_FLAGS'] = value.gsub("${PODS_ROOT}/#{library}/Prebuilt/", "#{development}/Prebuilt/")
      xcconfig.save_as(aggregate.xcconfig_path(name))
    end
  end
end
