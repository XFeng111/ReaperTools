-- 开始撤销块
reaper.Undo_BeginBlock()

-- 检查时间选区和item的有效性
local function check_time_selection_and_items()
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_time == end_time then
        reaper.ShowMessageBox("无时间选区，请先设置时间选区", "错误", 0)
        reaper.Undo_EndBlock("脚本运行：无时间选区", -1)
        return false
    end

    -- 选择当前时间选区中的所有对象
    reaper.Main_OnCommand(40717, 0)

    local num_selected_items = reaper.CountSelectedMediaItems(0)
    if num_selected_items == 0 then
        reaper.ShowMessageBox("框选时间选区下无item，请确保时间选区包含item", "错误", 0)
        reaper.Undo_EndBlock("脚本运行：框选时间选区下无item", -1)
        return false
    end

    local item_names = {}
    for i = 0, num_selected_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 0 then
            local take = reaper.GetActiveTake(item)
            if take then
                local item_name = reaper.GetTakeName(take)
                item_names[item_name] = (item_names[item_name] or 0) + 1
            end
        end
    end

    local has_same_name = false
    for _, count in pairs(item_names) do
        if count > 1 then
            has_same_name = true
            break
        end
    end

    if not has_same_name then
        reaper.ShowMessageBox("时间选区下的所有item无同名（处于静音状态的item除外），请确保存在同名非静音item", "错误", 0)
        reaper.Undo_EndBlock("脚本运行：时间选区下的所有item无同名（处于静音状态的item除外）", -1)
        return false
    end

    return true
end

-- 分组选中的非静音 item（仅时间选区内）
local function group_non_muted_items()
    local item_groups = {}
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local num_items = reaper.CountMediaItems(0)
    for i = 0, num_items - 1 do
        local item = reaper.GetMediaItem(0, i)
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end_pos = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if (item_pos >= start_time and item_pos < end_time) or (item_end_pos > start_time and item_end_pos <= end_time) then
            local take = reaper.GetActiveTake(item)
            if take and reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 0 then
                local item_name = reaper.GetTakeName(take)
                item_groups[item_name] = item_groups[item_name] or {}
                table.insert(item_groups[item_name], item)
            end
        end
    end
    return item_groups
end

-- 对每组 item 执行编组操作
local function group_items_in_groups(item_groups)
    for _, group in pairs(item_groups) do
        -- 取消所有 item 的选中状态
        reaper.SelectAllMediaItems(0, false)
        -- 选中当前组的所有 item
        for _, item in ipairs(group) do
            reaper.SetMediaItemSelected(item, true)
        end
        -- 执行对象编组操作
        reaper.Main_OnCommand(40032, 0)
    end
end

-- 记录每组第一个 item 的信息
local function record_first_item_info(item_groups)
    local first_item_info = {}
    for name, group in pairs(item_groups) do
        if #group > 1 then
            table.sort(group, function(a, b)
                return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
            end)
            local first_item = group[1]
            first_item_info[name] = {
                pos = reaper.GetMediaItemInfo_Value(first_item, "D_POSITION"),
                track = reaper.GetMediaItem_Track(first_item)
            }
        end
    end
    return first_item_info
end

-- 取消所有轨道的选中状态
local function deselect_all_tracks()
    local num_tracks = reaper.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        reaper.SetTrackSelected(track, false)
    end
end

-- 选中每组第一个 item 所在的轨道
local function select_tracks_to_clone(first_item_info)
    local tracks_to_clone = {}
    for _, info in pairs(first_item_info) do
        local track = info.track
        if not tracks_to_clone[track] then
            tracks_to_clone[track] = true
            reaper.SetTrackSelected(track, true)
        end
    end
    return tracks_to_clone
end

-- 获取新克隆的轨道
local function get_cloned_tracks(original_count)
    local cloned_tracks = {}
    local new_num_selected_tracks = reaper.CountSelectedTracks(0)
    for i = original_count, new_num_selected_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        table.insert(cloned_tracks, track)
    end
    return cloned_tracks
end

-- 清理每组第一个 item 位置的 item（仅时间选区内）
local function clean_first_item_positions(first_item_info)
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    for _, info in pairs(first_item_info) do
        local track = info.track
        local pos = info.pos
        local num_items_on_track = reaper.CountTrackMediaItems(track)
        -- 从最大索引开始递减，确保在删除item时不会影响后续索引
        for j = num_items_on_track - 1, 0, -1 do
            if j >= 0 and j < num_items_on_track then
                local item = reaper.GetTrackMediaItem(track, j)
                if item then
                    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_end_pos = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    -- 只删除在时间选区内且位置与记录的第一个位置完全相同的 item
                    if (item_pos >= start_time and item_pos < end_time) or (item_end_pos > start_time and item_end_pos <= end_time) then
                        if item_pos == pos then
                            reaper.DeleteTrackMediaItem(track, item)
                        end
                    end
                end
            end
        end
    end
end

-- 将同组其他 item 移动到第一个 item 的位置（仅时间选区内）
local function move_items_to_first_position(item_groups, first_item_info)
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    for name, group in pairs(item_groups) do
        if #group > 1 then
            local first_info = first_item_info[name]
            local first_pos = first_info.pos
            local first_track = first_info.track
            for j = 2, #group do
                local item = group[j]
                local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_end_pos = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                if (item_pos >= start_time and item_pos < end_time) or (item_end_pos > start_time and item_end_pos <= end_time) then
                    reaper.SetMediaItemInfo_Value(item, "D_POSITION", first_pos)
                    reaper.MoveMediaItemToTrack(item, first_track)
                end
            end
        end
    end
end

-- 检测所有 item 的时间轴位置，将相同时间轴位置的 item 列为一个新类别（仅时间选区内）
local function group_items_by_position()
    local item_position_groups = {}
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local num_items = reaper.CountMediaItems(0)
    for i = 0, num_items - 1 do
        local item = reaper.GetMediaItem(0, i)
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end_pos = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if (item_pos >= start_time and item_pos < end_time) or (item_end_pos > start_time and item_end_pos <= end_time) then
            local position = item_pos
            item_position_groups[position] = item_position_groups[position] or {}
            table.insert(item_position_groups[position], item)
        end
    end
    return item_position_groups
end

-- 依次选择每个类别中的所有 item，执行从编组中移除对象，再执行编组对象操作
local function group_and_remove_items(item_position_groups)
    for _, group in pairs(item_position_groups) do
        -- 取消所有 item 的选中状态
        reaper.SelectAllMediaItems(0, false)
        -- 选中当前组的所有 item
        for _, item in ipairs(group) do
            reaper.SetMediaItemSelected(item, true)
        end
        -- 执行从编组中移除对象操作
        reaper.Main_OnCommand(40033, 0)
        -- 执行编组对象操作
        reaper.Main_OnCommand(40032, 0)
    end
end

-- 将时间选区下的所有文件夹轨道的子轨颜色设置为和父轨一致，以父轨颜色为准
local function set_child_track_colors_to_parent()
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local num_tracks = reaper.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        if folder_depth > 0 then
            local parent_color = reaper.GetTrackColor(track)
            local child_depth = folder_depth - 1
            local j = i + 1
            while j < num_tracks do
                local child_track = reaper.GetTrack(0, j)
                local child_folder_depth = reaper.GetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH")
                if child_folder_depth < 0 then
                    child_depth = child_depth + child_folder_depth
                elseif child_folder_depth > 0 then
                    child_depth = child_depth - child_folder_depth
                end
                if child_depth < 0 then
                    break
                end
                local item_on_track = false
                local num_items_on_track = reaper.CountTrackMediaItems(child_track)
                for k = 0, num_items_on_track - 1 do
                    local item = reaper.GetTrackMediaItem(child_track, k)
                    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_end_pos = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    if (item_pos >= start_time and item_pos < end_time) or (item_end_pos > start_time and item_end_pos <= end_time) then
                        item_on_track = true
                        break
                    end
                end
                if item_on_track then
                    reaper.SetTrackColor(child_track, parent_color)
                end
                j = j + 1
            end
        end
    end
end

-- 主流程
if not check_time_selection_and_items() then
    return
end

local item_groups = group_non_muted_items()
group_items_in_groups(item_groups)

local first_item_info = record_first_item_info(item_groups)
deselect_all_tracks()
local tracks_to_clone = select_tracks_to_clone(first_item_info)
local original_selected_track_count = reaper.CountSelectedTracks(0)

-- 克隆选中的轨道
reaper.Main_OnCommand(40062, 0)
local cloned_tracks = get_cloned_tracks(original_selected_track_count)

clean_first_item_positions(first_item_info)
move_items_to_first_position(item_groups, first_item_info)

-- 新克隆的轨道执行选择轨道中的所有对象操作
reaper.Main_OnCommand(40421, 0)
-- 执行对象属性: 静音操作
reaper.Main_OnCommand(40719, 0)

-- 再次选择时间选区下的所有item
reaper.Main_OnCommand(40717, 0)

local item_position_groups = group_items_by_position()
group_and_remove_items(item_position_groups)

-- 将时间选区下的所有文件夹轨道的子轨颜色设置为和父轨一致，以父轨颜色为准
set_child_track_colors_to_parent()

-- 取消工程中所有轨道的选中状态
deselect_all_tracks()
-- 取消时间选区
reaper.Main_OnCommand(40020, 0)

-- 结束撤销块
reaper.Undo_EndBlock("脚本运行：处理同名 item 分组、克隆轨道等操作", -1)

reaper.UpdateArrange()
