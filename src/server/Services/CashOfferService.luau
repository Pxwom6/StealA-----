--!strict
--[[
	"Need $X more?" offers. Called where a purchase fails for lack of cash (BeltService buying off the belt,
	EconomyService adding a podium): instead of only "Not enough cash!", the player is offered the cheapest cash pack
	that covers the gap (Logic/CashOfferRules), sized from their steady income exactly like the store card.

	The offer is a suggestion only: the client shows a small card with the pack's Robux price and a buy button that
	opens Roblox's own purchase prompt. The cash itself is granted by MonetizationService's receipt handler, quoted
	at purchase time like any other pack. Never during the first-time tutorial, and at most one offer per
	Monetization.cashOffer.cooldownSeconds; otherwise (or when no pack covers the gap) the usual toast is shown.

	No EconomyService dependency (EconomyService calls this), so the amount is computed from session.packIncome.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local CashOfferRules = require(ReplicatedStorage.Shared.Logic.CashOfferRules)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local CashOfferService = {}

-- A purchase costing `price` just failed because the player has less cash. Shows the offer when one is allowed and
-- a pack covers the gap, otherwise the "Not enough cash!" toast.
function CashOfferService.notEnoughCash(session: Session, price: number)
	local now = os.clock()
	local offer: CashOfferRules.Offer? = nil
	if CashOfferRules.allowed(now, session.cashOfferAt, session.tutorial ~= nil, Monetization.cashOffer) then
		offer = CashOfferRules.pick(
			price - session.data.cash,
			session.packIncome,
			Monetization.storeProducts,
			Monetization.products :: any,
			Economy.cashPacks :: any,
			RunService:IsStudio()
		)
	end
	if offer == nil then
		Remotes.notify(session.player, Theme.text.notEnoughCash, "error")
		return
	end
	session.cashOfferAt = now
	Remotes.fire(session.player, "CashOffer", { key = offer.key, amount = offer.amount, shortfall = offer.shortfall })
	Analytics.custom(session, "cash_offer_shown", offer.amount, { offer.key })
end

return CashOfferService
