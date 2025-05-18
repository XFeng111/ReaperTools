-- 开始撤销块
reaper.Undo_BeginBlock()

-- 辅助函数：获取时间选区
local function get_time_selection()
    return reaper.GetSet_LoopTimeRange(0, 0, 0, 0, 0)
end

-- 辅助函数：检查时间选区是否有效
local function check_time_selection()
    local start_time, end_time = get_time_selection()
    if start_time == end_time then
        reaper.ShowMessageBox("请框选时间选区", "提示", 0)
        reaper.Undo_EndBlock("No time selection", -1)
        return false
    end
    return true
end

-- 辅助函数：获取时间选区下的项目
local function get_items_in_selection()
    local start_time, end_time = get_time_selection()
    local items = {}
    local num_items = reaper.CountMediaItems(0)
    for i = 0, num_items - 1 do
        local item = reaper.GetMediaItem(0, i)
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_start < end_time and item_end > start_time then
            table.insert(items, item)
        end
    end
    return items
end

-- 辅助函数：检查时间选区下是否有项目
local function check_items_in_selection()
    local items = get_items_in_selection()
    if #items == 0 then
        reaper.ShowMessageBox("时间框选范围下没有 item，请重新框选。", "提示", 0)
        reaper.Undo_EndBlock("No items in time selection", -1)
        return false
    end
    return true
end

-- 辅助函数：检查时间选区下的轨道是否已经是移入父级文件夹的结构
local function check_folder_structure()
    local items = get_items_in_selection()
    local relevant_tracks = {}
    for _, item in ipairs(items) do
        local track = reaper.GetMediaItem_Track(item)
        relevant_tracks[track] = true
    end

    for track in pairs(relevant_tracks) do
        local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        if folder_depth == -1 then
            local parent_folder = reaper.GetTrack(0, track_index - 1)
            if parent_folder then
                local parent_folder_depth = reaper.GetMediaTrackInfo_Value(parent_folder, "I_FOLDERDEPTH")
                if parent_folder_depth == 1 then
                    reaper.ShowMessageBox("时间选区下的轨道已为移入父级文件夹轨道的结构，不再运行。", "提示", 0)
                    reaper.Undo_EndBlock("Tracks already in folder structure", -1)
                    return true
                end
            end
        end
    end
    return false
end

-- 辅助函数：按起始位置排序项目
local function sort_items(items)
    table.sort(items, function(a, b)
        return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
    end)
end

-- 辅助函数：间隔项目 1 秒
local function space_items(items)
    local prev_end = 0
    for _, item in ipairs(items) do
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        if prev_end > 0 then
            local new_start = prev_end + 1
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_start)
        end
        prev_end = reaper.GetMediaItemInfo_Value(item, "D_POSITION") + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    end
end

-- 辅助函数：处理轨道名称
local function process_track_names(items)
    local processed_tracks = {}
    for _, item in ipairs(items) do
        local track = reaper.GetMediaItem_Track(item)
        if not processed_tracks[track] then
            processed_tracks[track] = true
            local take = reaper.GetActiveTake(item)
            if take then
                local _, item_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                -- 去除末尾 "_数字.wav"、"_数字" 和 ".wav" 字符
                item_name = item_name:gsub("_%d+%.wav$", "")
                item_name = item_name:gsub("_%d+$", "")
                item_name = item_name:gsub("%.wav$", "")
                reaper.GetSetMediaTrackInfo_String(track, "P_NAME", item_name, true)
            end
        end
    end
    return processed_tracks
end

-- 辅助函数：为每个轨道创建 region
local function create_regions(processed_tracks)
    local region_start_times = {}
    local region_end_times = {}
    for track in pairs(processed_tracks) do
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local first_item_start = math.huge
        local last_item_end = -math.huge
        local num_items_on_track = reaper.CountTrackMediaItems(track)
        for i = 0, num_items_on_track - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            first_item_start = math.min(first_item_start, item_start)
            last_item_end = math.max(last_item_end, item_end)
        end
        reaper.AddProjectMarker2(0, true, first_item_start, last_item_end, track_name, -1, 0)
        table.insert(region_start_times, first_item_start)
        table.insert(region_end_times, last_item_end)
    end
    return region_start_times, region_end_times
end

-- 辅助函数：将每个轨道移入新建文件夹轨道
local function move_tracks_to_folders(processed_tracks)
    for track in pairs(processed_tracks) do
        reaper.SetOnlyTrackSelected(track)
        reaper.Main_OnCommand(42785, 0)
        local folder_track = reaper.GetSelectedTrack(0, 0)
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        reaper.GetSetMediaTrackInfo_String(folder_track, "P_NAME", track_name, true)

        -- 获取子轨道的颜色
        local track_color = reaper.GetTrackColor(track)
        -- 确保颜色值有效
        if track_color then
            -- 将父级文件夹轨道颜色设置为子轨道颜色
            reaper.SetTrackColor(folder_track, track_color)
        end
    end
end

-- 辅助函数：确保父级文件夹轨道名称与子轨道名称一致
local function sync_folder_track_names(processed_tracks)
    for track in pairs(processed_tracks) do
        local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        if folder_depth == -1 then
            local parent_folder = reaper.GetTrack(0, track_index - 1)
            local parent_folder_depth = reaper.GetMediaTrackInfo_Value(parent_folder, "I_FOLDERDEPTH")
            if parent_folder_depth == 1 then
                local _, child_track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
                reaper.GetSetMediaTrackInfo_String(parent_folder, "P_NAME", child_track_name, true)
                -- 获取子轨道的颜色
                local child_track_color = reaper.GetTrackColor(track)
                -- 确保颜色值有效
                if child_track_color then
                    -- 将父级文件夹轨道颜色设置为子轨道颜色
                    reaper.SetTrackColor(parent_folder, child_track_color)
                end
            end
        end
    end
end

-- 辅助函数：将时间选区下所有 item 所在轨道的名称清空
local function clear_track_names(processed_tracks)
    for track in pairs(processed_tracks) do
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", true)
    end
end

-- 辅助函数：找到所有新创建 region 的最小起始时间和最大结束时间
local function find_region_time_range(region_start_times, region_end_times)
    local min_start_time = math.huge
    local max_end_time = -math.huge
    for _, start_time in ipairs(region_start_times) do
        min_start_time = math.min(min_start_time, start_time)
    end
    for _, end_time in ipairs(region_end_times) do
        max_end_time = math.max(max_end_time, end_time)
    end
    return min_start_time, max_end_time
end

-- 提取文件名的基础名
local function get_base_name(file_path)
    local file_name = string.match(file_path, "[^\\/]+$")
    return string.match(file_name, "^(.*)_%d+%.wav$") or string.gsub(file_name, "%.wav$", "")
end

-- 分组项目
local function group_items()
    local start_time, end_time = get_time_selection()
    local groups = {}
    local item_count = reaper.CountMediaItems(0)
    for i = 0, item_count - 1 do
        local item = reaper.GetMediaItem(0, i)
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item and item_start < end_time and item_end > start_time then
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

-- 检查所有项目分组是否已分别在独立轨道上
local function check_groups_on_separate_tracks(groups)
    if #groups == 1 then
        return false
    end
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

-- 按每组第一个项目的起始时间对所有组排序
local function sort_groups(groups)
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

-- 运行指定脚本的辅助函数
local function run_script(command_id)
    local command = reaper.NamedCommandLookup(command_id)
    if command then
        reaper.Main_OnCommand(command, 0)
    else
        reaper.ShowMessageBox("找不到指定的脚本命令: " .. command_id, "错误", 0)
    end
end

-- 辅助函数：确保时间选区下的所有 item 都被选中
local function ensure_items_selected(items)
    -- 先取消所有选中的项目
    reaper.Main_OnCommand(40289, 0)
    for _, item in ipairs(items) do
        reaper.SetMediaItemSelected(item, true)
    end
end

-- 主函数
local function main()
    -- 检查各项条件
    if not check_time_selection() or not check_items_in_selection() or check_folder_structure() then
        return
    end

    local groups = group_items()
    if not next(groups) then
        reaper.ShowMessageBox("框选的时间选区下没有项目", "提示", 0)
        reaper.Undo_EndBlock("No items in time selection", -1)
        return
    end

    -- 这里修改条件判断，确保单一分组也能处理
    if #groups > 1 and check_groups_on_separate_tracks(groups) then
        reaper.ShowMessageBox("所有项目分组已分别在独立轨道上，无需再次运行。", "提示", 0)
        reaper.Undo_EndBlock("Tracks already separated", -1)
        return
    end

    -- 对组内项目按时间轴顺序排序
    for _, items in pairs(groups) do
        sort_items(items)
    end

    local sorted_groups = sort_groups(groups)
    local start_time, _ = get_time_selection()
    local new_start_time, new_end_time = move_groups_to_separate_tracks(sorted_groups, start_time)
    set_new_time_range(new_start_time, new_end_time)

    local items = get_items_in_selection()
    sort_items(items)
    space_items(items)
    local processed_tracks = process_track_names(items)
    local region_start_times, region_end_times = create_regions(processed_tracks)
    move_tracks_to_folders(processed_tracks)
    sync_folder_track_names(processed_tracks)
    clear_track_names(processed_tracks)
    local min_start_time, max_end_time = find_region_time_range(region_start_times, region_end_times)
    set_new_time_range(min_start_time, max_end_time)

    reaper.UpdateArrange()

    ensure_items_selected(items)
    run_script("_RS06c6146f233b1e6cfc1f654e2c9b671552502f37")
    run_script("_RSdf339410c59229e095c4f17daff30782d6f51458")
end

main()

-- 结束撤销块
reaper.Undo_EndBlock("Process items in time selection", -1)