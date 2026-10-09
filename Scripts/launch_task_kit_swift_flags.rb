require_relative 'consumer_macro_flags'

def inject_launch_task_kit_swift_flags_if_needed(installer)
  inject_macro_flags(installer, 'LaunchTaskKit', 'LaunchTaskKitMacros', ['-enable-experimental-feature', 'SymbolLinkageMarkers'])
end
