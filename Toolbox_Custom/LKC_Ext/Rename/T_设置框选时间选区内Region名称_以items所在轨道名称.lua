--框选时间选区timeline
--选中时间选区timeline下的所有region
--检查区域内是否存在 Item，并记录这些 Item 所在轨道的名称（自动去重，确保同一轨道名称不重复）
--将region名称分别设置为各自范围内items所在轨道的名称

--注意事项
--1.时间重叠判断：
--只要 Item 与区域有部分时间重叠，就会被包含在内。
--2.轨道名称合并：
--如果区域内没有 Item，区域名称会变为空字符串。
--如果一个区域内有多个轨道，名称会按遍历顺序拼接。

--脚本功能
--1.遍历所有区域：
--使用 reaper.EnumProjectMarkers3 获取每个区域的起止时间 (pos 和 rgnend)。

--2.收集轨道名称：
--检查区域内是否存在 Item，并记录这些 Item 所在轨道的名称。
--自动去重，确保同一轨道名称不重复。

--3.更新区域名称：
--将轨道名称合并为逗号分隔的字符串（例如 "Vocal, Guitar"）。
--使用 reaper.SetProjectMarker3 更新区域名称。




-- 获取所有区域（Region）
local _, num_markers, num_regions = reaper.CountProjectMarkers(0)

-- 遍历所有标记和区域
for i = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(0, i)
    
    -- 只处理区域（Region）
    if isrgn then
        local track_names = {}  -- 存储轨道名称的列表
        local tracks = {}       -- 用于去重的轨道对象缓存
        
        -- 遍历所有 Media Item
        local num_items = reaper.CountMediaItems(0)
        for j = 0, num_items - 1 do
            local item = reaper.GetMediaItem(0, j)
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_start + item_length
            
            -- 检查 Item 是否与该区域有时间重叠
            if item_start < rgnend and item_end > pos then
                local track = reaper.GetMediaItem_Track(item)
                if track and not tracks[track] then
                    tracks[track] = true  -- 标记轨道已处理
                    local _, track_name = reaper.GetTrackName(track, "")
                    table.insert(track_names, track_name)
                end
            end
        end
        
        -- 合并轨道名称并更新区域名称
        local new_name = table.concat(track_names, ", ")
        reaper.SetProjectMarker3(0, markrgnindexnumber, true, pos, rgnend, new_name, color)
    end
end

-- 刷新界面
reaper.UpdateArrange()