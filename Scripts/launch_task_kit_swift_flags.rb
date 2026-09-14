require 'set'

def inject_launch_task_kit_swift_flags_if_needed(installer)
  flags = '$(inherited) -load-plugin-executable ${PODS_ROOT}/LaunchTaskKit/Prebuilt/LaunchTaskKitMacros#LaunchTaskKitMacros -enable-experimental-feature SymbolLinkageMarkers'
  inject_macro_flags_for_dependency(installer, 'LaunchTaskKit', 'LaunchTaskKitMacros', flags)
end

unless Object.private_method_defined?(:inject_macro_flags_for_dependency)
  def inject_macro_flags_for_dependency(installer, dependency_name, executable_name, flags)
    development_path = installer.sandbox.development_pods[dependency_name]&.expand_path
    development_root = development_path&.file? ? development_path.dirname : development_path
    installed_root = "${PODS_ROOT}/#{dependency_name}"
    resolved_flags = development_root ? flags.gsub(installed_root, development_root.to_s) : flags

    projects = [installer.pods_project]
    projects.concat(installer.generated_projects) if installer.respond_to?(:generated_projects)
    projects.compact!
    projects.uniq!

    target_map = projects.each_with_object({}) do |project, map|
      project.targets.each { |target| map[target.name] = target }
    end

    projects.each do |project|
      project.targets.each do |target|
        next if target.name.start_with?('Pods-')
        next unless macro_dependency?(target, dependency_name, target_map)

        target.build_configurations.each do |configuration|
          current_flags = configuration.build_settings['OTHER_SWIFT_FLAGS'] || '$(inherited)'
          next if current_flags.include?(executable_name)

          configuration.build_settings['OTHER_SWIFT_FLAGS'] = "#{current_flags} #{resolved_flags}"
        end
      end
    end

    return unless development_root

    installer.aggregate_targets.each do |aggregate_target|
      aggregate_target.xcconfigs.each do |configuration_name, xcconfig|
        current_flags = xcconfig.attributes['OTHER_SWIFT_FLAGS']
        next unless current_flags&.include?(installed_root)

        xcconfig.attributes['OTHER_SWIFT_FLAGS'] = current_flags.gsub(installed_root, development_root.to_s)
        xcconfig.save_as(aggregate_target.xcconfig_path(configuration_name))
      end
    end
  end

  def macro_dependency?(target, dependency_name, target_map, visited = Set.new)
    return false if visited.include?(target.name)

    visited.add(target.name)
    target.dependencies.any? do |dependency|
      name = dependency.name || dependency.target&.name
      next true if name == dependency_name

      dependency_target = dependency.target || target_map[name]
      dependency_target && macro_dependency?(dependency_target, dependency_name, target_map, visited)
    end
  end
end
