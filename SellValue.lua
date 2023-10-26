-- global SellValues = itemid -> price

local function hooksecurefunc(arg1, arg2, arg3)
	if type(arg1) == "string" then
		arg1, arg2, arg3 = _G, arg1, arg2
	end
	local orig = arg1[arg2]
	arg1[arg2] = function(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)
		local x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16, x17, x18, x19, x20 = orig(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)

		arg3(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)

		return x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16, x17, x18, x19, x20
	end
end

function SellValue_SetTooltip(itemID, stackCount, tooltip)
	if not tooltip then
		tooltip = GameTooltip
	end

	if not SellValues then
		return
	end
	local price = SellValues[itemID];
	if price then
		if price == 0 then
			tooltip:AddLine(ITEM_UNSELLABLE, 1.0, 1.0, 1.0);
		else
			SetTooltipMoney(tooltip, price * stackCount);

		end  -- if price > 0

		-- Adjust width and height to account for new lines
		tooltip:SetHeight(tooltip:GetHeight() + 14);
		if tooltip:GetWidth() < 120 then
			tooltip:SetWidth(120);
		end
	end  -- if price
end

function SellValue_OnLoad()

	-- Get initial prices from database
	SellValue_InitializeDB();

	this:RegisterEvent("MERCHANT_SHOW");

	SellValue_Saved_OnTooltipAddMoney = SellValue_Tooltip:GetScript("OnTooltipAddMoney");

	SellValue_Tooltip:SetScript("OnTooltipAddMoney", SellValue_OnTooltipAddMoney);

	-- Hook item links tooltip
	local org_OnHyperlinkShow = ChatFrame_OnHyperlinkShow
	function ChatFrame_OnHyperlinkShow(link, text, button)
		-- First, call the original function
		org_OnHyperlinkShow(link, text, button);

		-- Now, call your custom function
		local itemID = SellValue_IDFromLink(link);
		SellValue_SetTooltip(itemID, 1, ItemRefTooltip);
	end

	-- Hook loot tooltip
	hooksecurefunc(GameTooltip, "SetLootItem", function(tip, lootIndex)
		local _, _, stackCount = GetLootSlotInfo(lootIndex);
		if stackCount > 0 then
			local link = GetLootSlotLink(lootIndex);
			local itemID = SellValue_IDFromLink(link)

			SellValue_SetTooltip(itemID, stackCount);
		end
	end
	);

	-- Hook bag tooltip
	hooksecurefunc(GameTooltip, "SetBagItem", function(tip, bag, slot)
		if not MerchantFrame:IsVisible() then
			local _, stackCount = GetContainerItemInfo(bag, slot);
			local itemID = SellValue_GetItemID(bag, slot);

			SellValue_SetTooltip(itemID, stackCount);
		end
	end
	);


	-- Hook bank tooltip
	hooksecurefunc(GameTooltip, "SetInventoryItem", function(tip, unit, slot)
		if not MerchantFrame:IsVisible() and slot > 19 then
			local stackCount = GetInventoryItemCount(unit, slot);
			local itemID = SellValue_GetItemID(-1, slot);

			SellValue_SetTooltip(itemID, stackCount);
		end
	end
	);

	-- Hook quest reward tooltip
	hooksecurefunc(GameTooltip, "SetQuestItem", function(tip, qtype, slot)
		if qtype == "reward" or qtype == "choice" then
			local link = GetQuestItemLink(qtype, slot);
			local _, _, stackCount = GetQuestItemInfo(qtype, slot);
			local itemID = SellValue_IDFromLink(link);

			SellValue_SetTooltip(itemID, stackCount)
		end
	end
	);

	-- Hook questlog reward tooltip
	hooksecurefunc(GameTooltip, "SetQuestLogItem", function(tip, qtype, slot)
		local stackCount = nil;

		if qtype == "reward" then
			_, _, stackCount = GetQuestLogRewardInfo(slot);
		elseif qtype == "choice" then
			_, _, stackCount = GetQuestLogChoiceInfo(slot);
		else
			return
		end

		local link = GetQuestLogItemLink(qtype, slot);
		local itemID = SellValue_IDFromLink(link);

		SellValue_SetTooltip(itemID, stackCount);
	end
	);

	-- Hook trade skill tooltip
	hooksecurefunc(GameTooltip, "SetTradeSkillItem", function(tip, tradeItemIndex, reagentIndex)
		local stackCount = nil;
		local link = nil;

		if reagentIndex then
			_, _, stackCount = GetTradeSkillReagentInfo(tradeItemIndex, reagentIndex);
			link = GetTradeSkillReagentItemLink(tradeItemIndex, reagentIndex);
		else
			stackCount = GetTradeSkillNumMade(tradeItemIndex);
			link = GetTradeSkillItemLink(tradeItemIndex);
		end

		local itemID = SellValue_IDFromLink(link);
		SellValue_SetTooltip(itemID, stackCount);
	end
	);
end

function SellValue_OnEvent()
	if event == "MERCHANT_SHOW" then
		return SellValue_MerchantScan(this);
	end
end

SellValue_Saved_GameTooltip_OnEvent = GameTooltip_OnEvent;
GameTooltip_OnEvent = function()
	if event ~= "CLEAR_TOOLTIP" then
		return SellValue_Saved_GameTooltip_OnEvent();
	end
end

function SellValue_OnTooltipAddMoney ()
	-- call the original function first
	SellValue_Saved_OnTooltipAddMoney();

	-- The money in repair mode is the cost to repair, not sell
	if InRepairMode() then
		return ;
	end ;

	SellValue_LastItemMoney = arg1;
end

function SellValue_SaveFor(bag, slot, name, money)

	if not (bag and slot and name and money) then
		return ;
	end ;

	local _, stackCount = GetContainerItemInfo(bag, slot);
	if stackCount and stackCount > 0 then
		local costOfOne = money / stackCount;

		if not SellValues then
			SellValues = {};
		end

		SellValues[name] = costOfOne;
	end
end

function SellValue_MerchantScan(frame)

	for bag = 0, NUM_BAG_FRAMES do
		for slot = 1, GetContainerNumSlots(bag) do

			local itemName = SellValue_GetItemID(bag, slot);
			if itemName ~= "" then
				SellValue_LastItemMoney = 0;
				SellValue_Tooltip:SetBagItem(bag, slot);
				SellValue_SaveFor(bag, slot, itemName, SellValue_LastItemMoney);
			end  -- if item name
		end  -- for slot
	end -- for bag

end

function SellValue_OnHide()
	-- ClearMoney() expects this to point to the tooltip itself, and this here
	-- points to us, a child of the tip
	this = this:GetParent();
	return GameTooltip_ClearMoney();
end

function SellValue_GetItemID(bag, slot)
	local linktext = nil;

	if (bag == -1) then
		linktext = GetInventoryItemLink("player", slot);
	else
		linktext = GetContainerItemLink(bag, slot);
	end

	if linktext then
		return SellValue_IDFromLink(linktext);
	else
		return "";
	end
end

function SellValue_IDFromLink(itemlink)
	if itemlink then
		local foundlink, _, name = string.find(itemlink, "(item:%d+)");
		if foundlink then
			return name;
		else
			return itemlink;
		end
	end
	return ;
end
