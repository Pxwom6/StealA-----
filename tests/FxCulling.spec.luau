--!strict
local T = require("./TestKit")
local Gameplay = require("../src/shared/Config/Gameplay")
local FxCulling = require("../src/shared/Logic/FxCulling")

T.describe("FxCulling", function()
	local cfg = { onWithin = 90, offBeyond = 110, checkSeconds = 0.5 }
	T.it("switches far Snacklings' effects off and near ones back on, with a gap between", function()
		T.expect(FxCulling.shown(true, 50, cfg)).toBe(true)
		T.expect(FxCulling.shown(true, 110, cfg)).toBe(true)
		T.expect(FxCulling.shown(true, 111, cfg)).toBe(false)
		-- once off, they stay off until well inside
		T.expect(FxCulling.shown(false, 100, cfg)).toBe(false)
		T.expect(FxCulling.shown(false, 90, cfg)).toBe(true)
		-- no camera yet: no change
		T.expect(FxCulling.shown(true, 0 / 0, cfg)).toBe(true)
		T.expect(FxCulling.shown(false, 0 / 0, cfg)).toBe(false)
	end)
	T.it("accepts the shipped config and rejects one without a gap", function()
		T.expect(#FxCulling.validate(Gameplay.podiumFx)).toBe(0)
		T.expect(#FxCulling.validate({ onWithin = 100, offBeyond = 100, checkSeconds = 0.5 })).toBe(1)
		T.expect(#FxCulling.validate({ onWithin = 0, offBeyond = 100, checkSeconds = 0 })).toBe(2)
	end)
end)

return nil
