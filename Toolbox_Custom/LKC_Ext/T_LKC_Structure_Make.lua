-- 开始撤销块
reaper.Undo_BeginBlock()

-- 函数 1: 将时间选区下 item 所在的轨道，子轨道颜色和父轨道保持一致
function Sync_subtrack_color_with_parent_in_time_range()
    local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if start_time == end_time then
        reaper.ShowMessageBox("请设置时间选区", "错误", 0)
        return
    end

    local item_tracks = {}
    for i = 0, reaper.CountMediaItems(0) - 1 do
        local item = reaper.GetMediaItem(0, i)
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_start < end_time and item_end > start_time then
            local track = reaper.GetMediaItem_Track(item)
            item_tracks[track] = true
        end
    end

    for track in pairs(item_tracks) do
        local parent_color = reaper.GetTrackColor(track)
        local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        local num_tracks = reaper.CountTracks(0)
        for i = track_index + 1, num_tracks - 1 do
            local subtrack = reaper.GetTrack(0, i)
            local depth = reaper.GetMediaTrackInfo_Value(subtrack, "I_FOLDERDEPTH")
            if depth < 0 then
                reaper.SetTrackColor(subtrack, parent_color)
            else
                break
            end
        end
    end
end

--函数 2： 将时间选区下相邻item分组，历遍打pack
function Process_items_in_time_range()
    -- 选择时间选区下的所有 item
    local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if start_time == end_time then
        reaper.ShowMessageBox("请设置时间选区", "错误", 0)
        return
    end

    local items = {}
    for i = 0, reaper.CountMediaItems(0) - 1 do
        local item = reaper.GetMediaItem(0, i)
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_start < end_time and item_end > start_time then
            -- 修改字段名，避免使用保留关键字 end
            table.insert(items, { item = item, start = item_start, finish = item_end })
        end
    end

    -- 将时间范围有重合的 item 列为一组
    local groups = {}
    for _, item_info in ipairs(items) do
        local added = false
        for _, group in ipairs(groups) do
            for _, other_item_info in ipairs(group) do
                -- 修改字段名引用
                if (item_info.start <= other_item_info.finish and item_info.finish >= other_item_info.start) then
                    table.insert(group, item_info)
                    added = true
                    break
                end
            end
            if added then break end
        end
        if not added then
            table.insert(groups, { item_info })
        end
    end

    -- 取消所选择对象
    for i = 0, reaper.CountMediaItems(0) - 1 do
        local item = reaper.GetMediaItem(0, i)
        reaper.SetMediaItemSelected(item, false)
    end

    -- 依次历遍分组，选择每组下的 item，执行操作
    for _, group in ipairs(groups) do
        for _, item_info in ipairs(group) do
            reaper.SetMediaItemSelected(item_info.item, true)
        end
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS06c6146f233b1e6cfc1f654e2c9b671552502f37"), 0)
    end
end

--  选择时间选区下的所有 item
local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
if start_time == end_time then
    reaper.ShowMessageBox("请设置时间选区", "错误", 0)
    -- 结束撤销块
    reaper.Undo_EndBlock("脚本运行（未完成）", -1)
    return
end

local item_count = 0
local items = {}
for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if item_start < end_time and item_end > start_time then
        reaper.SetMediaItemSelected(item, true)
        item_count = item_count + 1
        table.insert(items, item)
    end
end

if item_count == 0 then
    reaper.ShowMessageBox("时间选区下没有 item", "错误", 0)
    -- 结束撤销块
    reaper.Undo_EndBlock("脚本运行（未完成）", -1)
    return
end

-- 检查时间选区下 item 的编组状态
local all_grouped = true
local all_ungrouped = true
for _, item in ipairs(items) do
    local group_id = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
    if group_id == 0 then
        all_grouped = false
    else
        all_ungrouped = false
    end
end

--如果均已打组
if all_grouped then
    reaper.ShowMessageBox("均已打组，无需再次运行", "错误", 0)
    -- 结束撤销块
    reaper.Undo_EndBlock("脚本运行（未完成）", -1)
    return
end

--如果均未打组
if all_ungrouped then
    -- 取消当前选中的轨道
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        reaper.SetTrackSelected(track, false)
    end

    -- 选中 item 所在的所有轨道
    local selected_tracks = {}
    for _, item in ipairs(items) do
        local track = reaper.GetMediaItem_Track(item)
        local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        if not selected_tracks[track_index] then
            selected_tracks[track_index] = track
            reaper.SetTrackSelected(track, true)
        end
    end

    -- 检查时间选区下 item 所在轨道的轨道层级
    for _, item in ipairs(items) do
        local track = reaper.GetMediaItem_Track(item)
        local track_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        if track_depth < 0 then
            --提示存在子轨，将子轨移出重新运行
            reaper.ShowMessageBox("时间选区下的 item 所在轨道存在子轨，请将子轨移出重新运行", "错误", 0)
            -- 取消当前选中的轨道
            for i = 0, reaper.CountTracks(0) - 1 do
                local track = reaper.GetTrack(0, i)
                reaper.SetTrackSelected(track, false)
            end

            --  取消选择 item 和时间选区
            for _, item in ipairs(items) do
                reaper.SetMediaItemSelected(item, false)
            end
            reaper.GetSet_LoopTimeRange2(0, true, false, 0, 0, false)
            -- 结束撤销块
            reaper.Undo_EndBlock("脚本运行（未完成）", -1)
            return
        end
    end

    --  将选择 item 所在的所有轨道移动到新建文件夹轨道
    local retval, folder_name = reaper.GetUserInputs("输入新建文件夹轨道名称", 1, "文件夹名称", "")
    if retval then
        -- 标记现有轨道
        local existing_tracks = {}
        for i = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            existing_tracks[track] = true
        end

        reaper.Main_OnCommand(42785, 0) -- 创建新建文件夹轨道

        -- 找出新创建的文件夹轨道
        local folder_track = nil
        for i = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            if not existing_tracks[track] then
                folder_track = track
                break
            end
        end

        if folder_track then
            -- 设置文件夹轨道名称
            local success = reaper.GetSetMediaTrackInfo_String(folder_track, "P_NAME", folder_name, true)
            if not success then
                reaper.ShowMessageBox("设置文件夹轨道名称失败", "错误", 0)
            end

            for _, track in pairs(selected_tracks) do
                -- 修改为使用 SetMediaTrackInfo_Value 设置父轨道
                local folder_track_index = reaper.GetMediaTrackInfo_Value(folder_track, "IP_TRACKNUMBER") - 1
                reaper.SetMediaTrackInfo_Value(track, "IP_PARENTTRACK", folder_track_index)
            end
        else
            reaper.ShowMessageBox("未找到新创建的文件夹轨道", "错误", 0)
        end
    end

    --  将时间选区适应于选择的所有 item，设置 region，region 名称设置为新建的文件夹轨道名称
    local min_start = math.huge
    local max_end = -math.huge
    for _, item in ipairs(items) do
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        min_start = math.min(min_start, item_start)
        max_end = math.max(max_end, item_end)
    end
    reaper.GetSet_LoopTimeRange2(0, true, false, min_start, max_end, false)
    reaper.AddProjectMarker2(0, true, min_start, max_end, folder_name, -1, 0)

    --  保持选中 item 状态，运行脚本: LKC - RenderBlocks - Pack clusters.lua
    -- 调用函数
    Process_items_in_time_range()

    --  运行脚本: LKC - RenderBlocks - AutoName.lua
    --对象: 选择当前时间选区中的所有对象 ⇌ Item: Select all items in current time selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("40717"), 0)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSdf339410c59229e095c4f17daff30782d6f51458"), 0)

    -- 子轨道颜色与父轨一致
    Sync_subtrack_color_with_parent_in_time_range()

    -- 结束撤销块
    reaper.Undo_EndBlock("脚本运行（未完成）", -1)
    return
end

-- 如果存在部分未编组的 item，移除时间选区下的所有 region
if not all_grouped and not all_ungrouped then
    -- 读取时间选区下的 region，将光标移动到 region 起始时间位置，执行删除光标附近的区域操作
    local num_markers = reaper.CountProjectMarkers(0)
    for i = num_markers - 1, 0, -1 do
        local _, is_region, start_pos, end_pos = reaper.EnumProjectMarkers3(0, i)
        if is_region and ((start_pos >= start_time and start_pos < end_time) or (end_pos > start_time and end_pos <= end_time)) then
            -- 将光标移动到 region 起始时间位置
            reaper.SetEditCurPos2(0, start_pos, false, false)
            -- 执行删除光标附近的区域操作
            reaper.Main_OnCommand(40615, 0)
        end
    end

    --对象: 选择当前时间选区中的所有对象 ⇌ Item: Select all items in current time selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("40717"), 0)
    --对象编组: 从编组中移除对象 ⇌ Item grouping: Remove items from group
    reaper.Main_OnCommand(reaper.NamedCommandLookup("40033"), 0)

    -- 取消所选择对象
    for i = 0, reaper.CountMediaItems(0) - 1 do
        local item = reaper.GetMediaItem(0, i)
        reaper.SetMediaItemSelected(item, false)
    end
    --SWS/BR: 选择所有空对象 (如有时间选区则遵循) ⇌ SWS/BR: Select all empty items (obey time selection, if any)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_SEL_ALL_ITEMS_TIME_SEL_EMPTY"), 0)
    --SWS/BR: 选择所有 MIDI 对象 (如有时间选区则遵循) ⇌ SWS/BR: Select all MIDI items (obey time selection, if any)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_SEL_ALL_ITEMS_TIME_SEL_MIDI"), 0)

    --移除对象/轨道/包络点 (取决于焦点) ⇌ Remove items/tracks/envelope points (depending on focus)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("40697"), 0)

    --提示已清理请重新运行
    reaper.ShowMessageBox("时间选区下存在未清除的item编组,已清理编组和空白对象,请重新运行", "错误", 0)
    -- 结束撤销块
    reaper.Undo_EndBlock("脚本运行（未完成）", -1)
    return
end

--  取消选择 item 和时间选区
for _, item in ipairs(items) do
    reaper.SetMediaItemSelected(item, false)
end

reaper.GetSet_LoopTimeRange2(0, true, false, 0, 0, false)

-- 取消当前选中的轨道
for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    reaper.SetTrackSelected(track, false)
end
reaper.GetSet_LoopTimeRange2(0, true, false, 0, 0, false)

-- 结束撤销块
reaper.Undo_EndBlock("脚本运行", -1)
