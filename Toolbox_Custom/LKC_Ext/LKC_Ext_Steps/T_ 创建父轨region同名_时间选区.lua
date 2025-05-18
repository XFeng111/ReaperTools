-- 开始撤销块
reaper.Undo_BeginBlock()

-- 辅助函数：获取时间选区
local function get_time_selection()
    return reaper.GetSet_LoopTimeRange(0, 0, 0, 0, 0)
end

-- 辅助函数：检查时间选区是否有效
local function is_time_selection_valid()
    local start_time, end_time = get_time_selection()
    if start_time == end_time then
        reaper.ShowMessageBox("请框选时间选区", "提示", 0)
        reaper.Undo_EndBlock("No time selection", -1)
        return false
    end
    return true
end

-- 辅助函数：获取时间选区下的项目
local function get_items_in_time_selection(start_time, end_time)
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
local function has_items_in_time_selection(items)
    if #items == 0 then
        reaper.ShowMessageBox("时间框选范围下没有 item，请重新框选。", "提示", 0)
        reaper.Undo_EndBlock("No items in time selection", -1)
        return false
    end
    return true
end

-- 辅助函数：检查时间选区下的轨道是否已经是移入父级文件夹的结构
local function is_already_in_folder_structure(items)
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
local function sort_items_by_start_time(items)
    table.sort(items, function(a, b)
        return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
    end)
end

-- 辅助函数：间隔项目 1 秒
local function space_items_by_one_second(items)
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

-- 检查前置条件
if not is_time_selection_valid() then
    return
end

local start_time, end_time = get_time_selection()
local items = get_items_in_time_selection(start_time, end_time)

if not has_items_in_time_selection(items) or is_already_in_folder_structure(items) then
    return
end

-- 按起始位置排序项目
sort_items_by_start_time(items)

-- 间隔项目 1 秒
space_items_by_one_second(items)

-- 处理轨道名称
local processed_tracks = process_track_names(items)

-- 为每个轨道创建 region
local region_start_times, region_end_times = create_regions(processed_tracks)

-- 将每个轨道移入新建文件夹轨道
move_tracks_to_folders(processed_tracks)

-- 确保父级文件夹轨道名称与子轨道名称一致
sync_folder_track_names(processed_tracks)

-- 将时间选区下所有 item 所在轨道的名称清空
clear_track_names(processed_tracks)

-- 找到所有新创建 region 的最小起始时间和最大结束时间
local min_start_time, max_end_time = find_region_time_range(region_start_times, region_end_times)

-- 设置时间选区到所有新创建的 region
reaper.GetSet_LoopTimeRange(1, 1, min_start_time, max_end_time, 0)

reaper.UpdateArrange()

-- 确保时间选区下的所有 item 被选中
for _, item in ipairs(items) do
    reaper.SetMediaItemSelected(item, true)
end

-- 结束撤销块
reaper.Undo_EndBlock("Process items in time selection", -1)    