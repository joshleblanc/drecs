$gtk.disable_controller_config!
GTK.ffi_misc.gtk_dlopen("flecs-ext")

require "external/ffi/struct"

# include FFI::FLECS



#require "lib/drecs"
require "samples/#{$gtk.cli_arguments.sample}/app/main"