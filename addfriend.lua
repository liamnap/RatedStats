-- Monitor target changes
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_TARGET_CHANGED")

f:SetScript("OnEvent", function()
      -- Only show for player targets
      if not UnitExists("target") or not UnitIsPlayer("target") then
         if TargetFrame.AddFriendIcon then
            TargetFrame.AddFriendIcon:Hide()
         end
         return
      end
      
      -- Show existing icon if it already exists
      if TargetFrame.AddFriendIcon then
         TargetFrame.AddFriendIcon:Show()
         return
      end
      
      -- Create clickable icon next to the target's name
      local icon = CreateFrame("Button", nil, TargetFrame)
      icon:SetSize(30, 30)
      icon:SetPoint("LEFT", TargetFrame.name, "RIGHT", -5, 0)
      
      local tex = icon:CreateTexture(nil, "OVERLAY")
      tex:SetAllPoints(true)
      
      -- ✅ Use the official Blizzard friend plus icon
      tex:SetTexture("Interface\\FriendsFrame\\PlusManz-PlusManz.blp")
      
      icon.texture = tex
      
      -- Tooltip behavior
      icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Rated Stats: Add Friend!", 1, 1, 1)
            GameTooltip:Show()
      end)
      icon:SetScript("OnLeave", function()
            GameTooltip:Hide()
      end)
      
      -- On click: send BNet friend request
      icon:SetScript("OnClick", function()
            BNCheckBattleTagInviteToUnit("target")
      end)
      
      -- Store the icon so we don’t recreate it
      TargetFrame.AddFriendIcon = icon
end)
