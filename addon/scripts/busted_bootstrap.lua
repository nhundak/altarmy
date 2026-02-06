-- Bootstrap for busted. Run as: lua scripts/busted_bootstrap.lua [spec path...]
-- Prepend vendored busted (cwd = project root) so busted and deps are found.
-- With no args, .busted sets ROOT = { "spec" } (top-level spec/, outside addon zip).
package.path = "busted-2.1.1/?.lua;busted-2.1.1/?/init.lua;" .. package.path
require("busted.runner")()
