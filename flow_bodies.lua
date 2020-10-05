--- This module defines bodies used to build control-flow operations, e.g. @{coroutine_ops.flow}.

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
local max = math.max
local min = math.min
local yield = coroutine.yield

-- Modules --
local meta = require("tektite_core.table.meta")

-- Exports --
local M = {}

--
--
--

local function Process (config)
	return config.yvalue == nil and "keep" or config.yvalue, not config.negate_done, config.use_time
end

--- Body for control-flow operations.
--
-- Once invoked, this will spin on a test / update loop until told to terminate. On each
-- iteration, if it did not terminate, it will yield.
-- @tparam ?|callable|nil update Update logic, called as
--    result = update(arg1, arg2, arg3)
-- after _done_. If **nil**, this is a no-op.
--
-- If _result_ is **"done"**, the body will terminate early.
-- @callable done Test, with same signature as _update_, called on each iteration. When
-- _result_ resolves to true (by default, if it is true), the loop terminates.
-- @ptable config Configuration parameters.
--
-- If the **negate_done** field is true, the _result_ from _done_ is negated, i.e. instead
-- of "until test passes" the loop is interpreted as "while test passes", and vice versa.
--
-- If a **yvalue** field is present, this value is yielded after each iteration. If absent,
-- this defaults to **"keep"**, as a convenience for coroutine-based @{TaskQueue} tasks.
-- @param arg1 Argument #1.
-- @param arg2 Argument #2.
-- @param arg3 Argument #3.
-- @treturn boolean Operation completed normally, i.e. _done_ resolved true?
function M.Body (update, done, config, arg1, arg2, arg3)
	assert(meta.CanCall(done), "Uncallable done")
	assert(update == nil or meta.CanCall(update), "Uncallable update")

	local yvalue, failure = Process(config)

	while true do
		local finished = not done(arg1, arg2, arg3) ~= failure

		-- Update any user-defined logic, quitting on an early exit or if already done.
		if finished or (update ~= nil and update(arg1, arg2, arg3) == "done") then
			return finished
		end

		yield(yvalue)
	end
end

local function Clamp (alapse, lapse)
	return max(0, min(alapse, lapse))
end

local TimeState = {}

local Deduct, Lapse

local function NoDeduct () end

local function NoLapse () return 0 end

--- Timed variant of @{Body}.
--
-- The current time lapse behavior at the time of the call will be used throughout the body,
-- even if @{SetTimeLapseFuncs} is called again before the body has concluded.
--
-- Logically, this body maintains a counter, _time_, which begins at 0. On each iteration,
-- time lapse function is polled for a value, _lapse_, &ge; 0. After test / update, if the
-- body-based operation has not concluded, _time_ will be incremented by _lapse_ (possibly
-- reduced by _update_ and / or _done_), just before the body yields for that iteration.
--
-- On each iteration, the final value of _lapse_ will also be deducted from the "time bank",
-- before yielding or returning.
-- @tparam ?|callable|nil update As per @{Body}, but called as
--    result, true_lapse = update(time_state, arg1, arg2, arg3)
-- If _result_ is **"done"**, _true\_lapse_ is also considered. If present, it indicates how
-- much time actually passed before the update terminated, and will replace the current time
-- lapse (assuming it is a shorter lapse and non-negative).
--
-- _time\_state_ is a table with the following fields:
--
-- * **time**: The current value of _time_.
-- * **lapse**: The current value of _lapse_ (possibly reduced by _done_).
--
-- @callable done Test performed on each iteration, called as
--    is_done[, true_lapse] = done([time_state, ]arg1, arg2, arg3)
-- If _is\_done_ is true, the loop is ready to terminate. In that case, _true\_lapse_ may
-- also be considered, as per _update_; otherwise, the amount is assumed to be 0, i.e. the
-- loop terminated instantly. If _true\_lapse_ &gt; 0, _update_ will still be called, using
-- the narrowed time lapse.
--
-- _time\_state_ is as per _update_, except the **lapse** amount will be the initial value
-- for the current iteration.
--
-- @ptable config As per @{Body}, though a **use_time** field is also examined. If this is
-- true, _done_ accepts the _time\_state_ argument and handles _true\_lapse_ on termination.
-- @param arg1 Argument #1.
-- @param arg2 Argument #2.
-- @param arg3 Argument #3.
-- @treturn boolean Operation concluded normally?
function M.Body_Timed (update, done, config, arg1, arg2, arg3)
	assert(meta.CanCall(done), "Uncallable done")
	assert(update == nil or meta.CanCall(update), "Uncallable update")

	local time, yvalue, failure, use_time = 0, Process(config)
	local lapse_func, deduct = Lapse or NoLapse, Deduct or NoDeduct

	while true do
		local lapse = lapse_func()

		-- Call the appropriate done logic, depending on whether we care about time, and
		-- decide whether the body is done (at least by the end of the iteration).
		local done_result, alapse_done

		if use_time then
			TimeState.time, TimeState.lapse = time, lapse

			done_result, alapse_done = done(TimeState, arg1, arg2, arg3)
		else
			done_result = done(arg1, arg2, arg3)
		end

		local finished = not done_result ~= failure

		-- If the done logic worked, the loop is ready to terminate. In this case, find
		-- out how much time passed on this iteration, erring toward none.
		alapse_done = finished and Clamp(alapse_done or 0, lapse)

		-- If the loop is not ready to terminate, or it is but it took some time, update
		-- any user-defined logic with however much time is now available. If there was an
		-- early exit there, find out how much of this time passed, erring toward all of it.
		local elapse_result, alapse_update

		if update ~= nil and (not finished or alapse_done > 0) then
			TimeState.time, TimeState.lapse = time, alapse_done or lapse

			elapse_result, alapse_update = update(TimeState, arg1, arg2, arg3)
		end

		alapse_update = elapse_result == "done" and Clamp(alapse_update or lapse, alapse_done or lapse)

		-- Deduct however much time passed on this iteration from the store. If ready, quit.
		if finished or elapse_result == "done" then
			deduct(alapse_update or alapse_done)

			return elapse_result ~= "done"
		else
			deduct(lapse)
		end

		time = time + lapse

		yield(yvalue)
	end
end

--- DOCME
-- **N.B.** This calls the lapse function assigned via @{SetTimeLapseFuncs}, if any, so
-- will trigger any side effects.
-- @treturn number Lapse
function M.GetLapse ()
	return (Lapse or NoLapse)()
end

--- Assigns the time lapse functions used by @{Body_Timed}.
--
-- The lapse function tells us how much time is available **right now** to run a timed body
-- operation. It may be the case that only some of this is needed: a useful abstraction
-- here is a "time bank", where the "balance"&mdash;viz. the entire time slice&mdash;is
-- reported, then the deduct function is told how much to "withdraw".
--
-- In this way, say, a 10-millisecond wait need not consume a 100-millisecond time slice.
-- Indeed, two consecutive 10-millisecond waits could run and still leave more: the lapse
-- would first report 100 milliseconds available, then 90, and so on.
--
-- **N.B.** It is up to the user to decide on the unit of time and employ it consistently.
-- @tparam ?|callable|nil lapse Lapse function to assign, which returns a time lapse as a
-- non-negative number; or **nil** to restore the default (which returns 0).
-- @tparam ?|callable|nil deduct Deduct function to assign, which accepts a non-negative
-- lapse amount and deducts it from the "time bank"; or **nil** to restore the default (a
-- no-op).
function M.SetTimeLapseFuncs (lapse, deduct)
	assert(lapse == nil or meta.CanCall(lapse), "Uncallable lapse function")
	assert(deduct == nil or meta.CanCall(deduct), "Uncallable deduct function")

	Lapse, Deduct = lapse, deduct
end

return M