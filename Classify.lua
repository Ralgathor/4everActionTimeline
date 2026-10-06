-- 4everActionTimeline — swing-event classification.
-- Turns the library's swing events into a reason (parry, retry, rescale,
-- reset, swap, early landing) from their signature. A copy of
-- 4everSwingTimer's rules (Bars.lua SwingStart / SwingStop) with its exact
-- thresholds, so both addons classify the same event the same way.
-- MARKED FOR REMOVAL once the library reports a reason on its swing events
-- (the library API ask, docs/SPEC.md Hand-lane effects).
--
-- Pure rules on a hand's state table; no effects here (Hands.lua maps each
-- reason to its treatment). Plain payload arithmetic only.

local Addon = FourEverActionTimeline

local abs, max = math.abs, math.max

local Classify = {
	-- The ranged movement-retry recast window (the library measured real
	-- recasts at 0.43-0.56 s; the bounds are padded).
	RETRY_MIN = 0.3,
	RETRY_MAX = 0.7,
	-- How long an in-flight STOP waits for its START before it counts as cut short.
	STOP_GRACE = 0.10,
	-- The grace plus a frame of slack: how long after a STOP its START may follow.
	STOP_WINDOW = 0.15,
	-- Less than this remaining at a STOP is a natural landing (the engine's
	-- swing and the library's timer race by up to a frame), not an early one.
	EARLY_LANDING_EPSILON = 0.2,
	-- Same weapon speed within 2 % (floor 0.01 s): an early landing, not a swap.
	SPEED_MATCH = 0.02,
	-- A swing this far past its expiry with no STOP has landed: it parks.
	STALE_LANDING_GRACE = 1.0,
}
Addon.Classify = Classify

-- A START: nil for a landing, else "reset" (a START while the swing is still
-- in flight - the cast-completion reset, whose STOP the library suppresses),
-- "early" (an in-flight STOP then a same-speed START within the grace) or
-- "swap" (the same, at a different weapon speed).
function Classify.Start(state, speed, now)
	if state.active and state.expiration and state.expiration > now + 0.05 then
		return "reset"
	end
	if state.stoppedInFlight and now - state.stoppedAt <= Classify.STOP_WINDOW then
		state.stoppedInFlight = nil
		local before = state.speedAtStop
		if before and abs(speed - before) <= max(before * Classify.SPEED_MATCH, 0.01) then
			return "early"
		end
		return "swap"
	end
	return nil
end

-- An UPDATE mid-swing: ranged "retry" (the movement-cancelled Auto Shot
-- re-attempted ~0.5 s ahead; the window takes precedence) or "rescale" (a
-- shortened shot - dynamic haste); melee "parry" (on Forever nothing else
-- produces a melee UPDATE). nil when nothing classifiable changed.
function Classify.Update(hand, state, expiration, now)
	if not state.active then
		return nil
	end
	if hand == "ranged" then
		local recast = expiration - now
		if recast > Classify.RETRY_MIN and recast < Classify.RETRY_MAX then
			return "retry"
		elseif state.expiration and expiration < state.expiration then
			return "rescale"
		end
		return nil
	end
	return "parry"
end

-- A STOP: records whether the swing was still in flight; which of early
-- landing, swap or cut short it was is only known when the next START does
-- or does not follow within STOP_GRACE.
function Classify.Stop(state, now)
	state.stoppedInFlight = (state.active and state.expiration and state.expiration > now + Classify.EARLY_LANDING_EPSILON) or nil
	state.stoppedAt = now
	state.speedAtStop = state.speed
end
