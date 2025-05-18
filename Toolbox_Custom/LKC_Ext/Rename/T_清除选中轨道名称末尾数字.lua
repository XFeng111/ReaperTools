-- 遍历所有选中的轨道
local num_selected_tracks = reaper.CountSelectedTracks(0)
for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
        -- 获取轨道名称
        local _, current_name = reaper.GetTrackName(track, "")
        
        -- 删除末尾的 "_数字"
        local new_name = current_name:gsub("_%d+$", "")
        
        -- 如果名称有变化，则更新
        if new_name ~= current_name then
            reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
        end
    end
end

-- 刷新界面
reaper.UpdateArrange()