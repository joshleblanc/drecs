# Drecs::Parallel - thin Ruby loader for the parallel runtime extension.
#
# The C extension (drecs_parallel.dll/.so) provides a kernel runner that
# fans work out across SDL3 threads. User-authored kernels live in
# *separate* DragonRuby C extensions and are referenced by their hosting
# module name + symbol name.
#
# Loading flow:
#
#   DR.dlopen "drecs_parallel"           # this runtime
#   DR.dlopen "my_systems"               # your kernels
#   Drecs::Parallel.load                 # marks runtime ready
#
# Drecs's World#register_native_system handles the rest.

module Drecs
  module Parallel
    @available = false
    @loaded = false

    class << self
      def available?
        @available
      end

      def loaded?
        @loaded
      end

      # Mark the runtime as loaded. Safe to call repeatedly. The C
      # extension itself must already be dlopen'd by the caller.
      def load
        return if @loaded
        @loaded = true

        if ::Drecs::Parallel.const_defined?(:AVAILABLE) && ::Drecs::Parallel::AVAILABLE
          begin
            init
            @available = true
          rescue StandardError => e
            warn "Drecs: Parallel runtime init failed: #{e.message}"
            @available = false
          end
        else
          @available = false
        end
      end

    # Resolve a kernel function pointer from a user extension's mruby
    # module. Returns the cptr (opaque) on success or raises on miss.
    #
    #   kernel_ptr("MySystems", :integrate_motion)
    #
    # Looks up `MySystems._kernel_integrate_motion`, which is the thunk
    # produced by DRECS_KERNEL_EXPORT in the user's C source.
    def kernel_ptr(module_name, kernel_symbol)
      mod = Object.const_get(module_name.to_s)
      getter = "_kernel_#{kernel_symbol}".to_sym
      unless mod.respond_to?(getter)
        raise NameError,
          "drecs: #{module_name}.#{getter} not found. " \
          "Did you DR.dlopen the extension and call DRECS_KERNEL_EXPORT/REGISTER for :#{kernel_symbol}?"
      end
      mod.send(getter)
    end
    end
  end
end
