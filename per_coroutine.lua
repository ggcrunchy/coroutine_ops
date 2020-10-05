--- This module defines some support for events that can be tailored to their host coroutine.

--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
-- [ MIT license: http://www.opensource.org/licenses/mit-license.php ]
--

-- Standard library imports --
local assert = assert
local running = coroutine.running

-- Modules --
local meta = require("tektite_core.table.meta")

-- Exports --
local M = {}

--
--
--

--- Make a function that can assume different behavior for each coroutine.
-- @treturn function Function which takes a single argument and passes it to the logic
-- registered for the current coroutine, returning any results. If no behavior is assigned,
-- or this is called from outside any coroutine, this is a no-op.
-- @treturn function Setter function, which must be called within a coroutine. The function
-- passed as its argument is assigned as the coroutine's behavior; it may be cleared
-- by passing **nil**.
--
-- It is also possible to pass **"exists"** as argument, which will return **true** if a
-- function is assigned to the current coroutine.
-- TODO: revise this!
function M.MakeValue ()
	local list = meta.WeakKeyed()

	return function(value)
		local coro = assert(running(), "Called outside a coroutine")

		if value == nil then
			return list[coro]
		else
			list[coro] = value
		end
	end
end

return M