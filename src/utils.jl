# Utilities for Giac.jl
# Thread safety, type conversion, and helper functions

"""
Global lock for serializing GIAC library calls.
GIAC is not thread-safe, so all calls must be serialized.
"""
const GIAC_LOCK = ReentrantLock()

"""
    with_giac_lock(f)

Execute function `f` while holding the GIAC lock.
Ensures thread-safe access to GIAC library.
"""
function with_giac_lock(f)
    lock(GIAC_LOCK) do
        _free_doomed!()          # objects finalizers left to free, see wrapper.jl
        f()
    end
end

# Note: to_julia, is_numeric, and is_symbolic have been moved to
# conversion.jl and introspection.jl as part of feature 029-output-handling
