-- 获取选中的时间范围
local function get_selected_time_range()
    return reaper.GetSet_LoopTimeRange(0, 0, 0, 0, 0)
end

-- 检查是否框选了时间选区
local function is_time_range_selected(start_time, end_time)
    return start_time ~= end_time
end

-- 提示用户框选时间选区
local function prompt_select_time_range()
    reaper.ShowMessageBox("请先框选时间选区", "提示", 0)
end

-- 获取所有项目数量
local function get_total_items()
    return reaper.CountMediaItems(0)
end

-- 提取文件名的基础名
local function get_base_name(file_path)
    local file_name = string.match(file_path, "[^\\/]+$")
    return string.match(file_name, "^(.*)_%d+%.wav$") or string.gsub(file_name, "%.wav$", "")
end

-- 检查项目是否在选中的时间范围内
local function is_item_in_selected_range(item, start_time, end_time)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    return item_start < end_time and item_end > start_time
end

-- 分组项目
local function group_items(start_time, end_time)
    local groups = {}
    local item_count = get_total_items()
    for i = 0, item_count - 1 do
        local item = reaper.GetMediaItem(0, i)
        if item and is_item_in_selected_range(item, start_time, end_time) then
            local take = reaper.GetActiveTake(item)
            if take then
                local file_path = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(take), "")
                local base_name = get_base_name(file_path)
                if base_name then
                    groups[base_name] = groups[base_name] or {}
                    table.insert(groups[base_name], item)
                end
            end
        end
    end
    return groups
end

-- 检查框选的时间选区下是否有项目
local function has_items_in_selection(groups)
    return next(groups) ~= nil
end

-- 提示框选的时间选区下没有项目
local function prompt_no_items_in_selection()
    reaper.ShowMessageBox("框选的时间选区下没有项目", "提示", 0)
end

-- 检查所有项目分组是否已分别在独立轨道上
local function are_groups_on_separate_tracks(groups)
    local track_map = {}
    for _, items in pairs(groups) do
        local first_item_track = reaper.GetMediaItem_Track(items[1])
        local group_on_single_track = true
        for _, item in ipairs(items) do
            if reaper.GetMediaItem_Track(item) ~= first_item_track then
                group_on_single_track = false
                break
            end
        end
        if not group_on_single_track or track_map[first_item_track] then
            return false
        end
        track_map[first_item_track] = true
    end
    return true
end

-- 提示所有项目分组已分别在独立轨道上
local function prompt_all_groups_on_separate_tracks()
    reaper.ShowMessageBox("所有项目分组已分别在独立轨道上，无需再次运行。", "提示", 0)
end

-- 对组内项目按时间轴顺序排序
local function sort_items_by_start_time(items)
    table.sort(items, function(a, b)
        return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
    end)
end

-- 按每组第一个项目的起始时间对所有组排序
local function sort_groups_by_first_item_start_time(groups)
    local sorted_groups = {}
    for _, items in pairs(groups) do
        table.insert(sorted_groups, items)
    end
    table.sort(sorted_groups, function(a, b)
        return reaper.GetMediaItemInfo_Value(a[1], "D_POSITION") < reaper.GetMediaItemInfo_Value(b[1], "D_POSITION")
    end)
    return sorted_groups
end

-- 移动每组项目到单独的轨道，并设置组间间隔 2 秒
local function move_groups_to_separate_tracks(sorted_groups, start_time)
    local current_track_index = reaper.CountTracks(0)
    local last_group_end_time = 0
    local new_start_time = math.huge
    local new_end_time = -math.huge
    for _, items in ipairs(sorted_groups) do
        if current_track_index >= reaper.CountTracks(0) then
            reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        end
        local target_track = reaper.GetTrack(0, current_track_index)
        local current_group_start_time = math.max(last_group_end_time + 2, start_time)
        for _, item in ipairs(items) do
            local offset = reaper.GetMediaItemInfo_Value(item, "D_POSITION") - start_time
            reaper.MoveMediaItemToTrack(item, target_track)
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", current_group_start_time + offset)
            local new_item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local new_item_end = new_item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            new_start_time = math.min(new_start_time, new_item_start)
            new_end_time = math.max(new_end_time, new_item_end)
        end
        local last_item = items[#items]
        last_group_end_time = reaper.GetMediaItemInfo_Value(last_item, "D_POSITION") + reaper.GetMediaItemInfo_Value(last_item, "D_LENGTH")
        current_track_index = current_track_index + 1
    end
    return new_start_time, new_end_time
end

-- 设置新的时间选区
local function set_new_time_range(new_start_time, new_end_time)
    reaper.GetSet_LoopTimeRange(1, 1, new_start_time, new_end_time, 1)
end

-- 主函数
local function main()
    local start_time, end_time = get_selected_time_range()
    if not is_time_range_selected(start_time, end_time) then
        prompt_select_time_range()
        return
    end

    local groups = group_items(start_time, end_time)
    if not has_items_in_selection(groups) then
        prompt_no_items_in_selection()
        return
    end

    if are_groups_on_separate_tracks(groups) then
        prompt_all_groups_on_separate_tracks()
        return
    end

    for _, items in pairs(groups) do
        sort_items_by_start_time(items)
    end

    local sorted_groups = sort_groups_by_first_item_start_time(groups)
    local new_start_time, new_end_time = move_groups_to_separate_tracks(sorted_groups, start_time)
    set_new_time_range(new_start_time, new_end_time)

    reaper.UpdateArrange()
end

main()    