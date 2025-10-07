$gtk.disable_controller_config!

require "lib/drecs"

if $gtk.cli_arguments.sample
    require "samples/#{$gtk.cli_arguments.sample}/app/main"
end
