-- Bootstrap for busted. Run as: lua scripts/busted_bootstrap.lua AltArmy_TBC
-- Prepend vendored busted (cwd = project root) so busted and deps are found.
-- arg[0]=script, arg[1]=AltArmy_TBC; busted uses both as ROOTs (first has no _spec, second has specs).
package.path = "busted-2.1.1/?.lua;busted-2.1.1/?/init.lua;" .. package.path
require("busted.runner")()
