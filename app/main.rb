$gtk.disable_controller_config!
GTK.ffi_misc.gtk_dlopen("flecs-ext")

include FFI::FLECS

#require "lib/drecs"
#require "samples/#{$gtk.cli_arguments.sample}/app/main"