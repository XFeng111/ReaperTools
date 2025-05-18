-- 开始撤销块
reaper.Undo_BeginBlock()

-- 检测是否框选时间选区
start_time, end_time = reaper.GetSet_LoopTimeRange(0, 0, 0, 0, 0)
if start_time == end_time then
    reaper.ShowMessageBox("请框选时间选区", "提示", 0)
    reaper.Undo_EndBlock("No time selection", -1)
    return
end

-- 获取时间选区范围内的所有 item
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

-- 处理轨道名称
local processed_tracks = {}
for _, item in ipairs(items) do
    local track = reaper.GetMediaItem_Track(item)
    if not processed_tracks[track] then
        processed_tracks[track] = true
        local take = reaper.GetActiveTake(item)
        if take then
            local _, item_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            -- 清除末尾的 _d.wav
            item_name = item_name:gsub("_%d+%.wav$", "")
            reaper.GetSetMediaTrackInfo_String(track, "P_NAME", item_name, true)
        end
    end
end

-- 存储新创建的文件夹轨道及其对应的子轨道
local new_folder_tracks = {}
-- 将每个轨道移入新建文件夹轨道
for track in pairs(processed_tracks) do
    reaper.SetOnlyTrackSelected(track)
    reaper.Main_OnCommand(42785, 0)
    local folder_track = reaper.GetSelectedTrack(0, 0)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    reaper.GetSetMediaTrackInfo_String(folder_track, "P_NAME", track_name, true)
    new_folder_tracks[folder_track] = track
end

-- 确保父级文件夹轨道名称与子轨道名称一致
for folder_track, track in pairs(new_folder_tracks) do
    local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if folder_depth == -1 then
        local parent_folder = reaper.GetTrack(0, track_index - 1)
        local parent_folder_depth = reaper.GetMediaTrackInfo_Value(parent_folder, "I_FOLDERDEPTH")
        if parent_folder_depth == 1 then
            local _, child_track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            reaper.GetSetMediaTrackInfo_String(parent_folder, "P_NAME", child_track_name, true)
        end
    end
end

-- 将时间选区下所有item所在轨道的名称清空
for track in pairs(processed_tracks) do
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", true)
end

-- 将时间选区下的父级文件夹轨道颜色设置为和子文件夹一致
for folder_track, track in pairs(new_folder_tracks) do
    local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if folder_depth == -1 then
        local parent_folder = reaper.GetTrack(0, track_index - 1)
        local parent_folder_depth = reaper.GetMediaTrackInfo_Value(parent_folder, "I_FOLDERDEPTH")
        if parent_folder_depth == 1 then
            local child_color = reaper.GetTrackColor(track)
            reaper.SetTrackColor(parent_folder, child_color)
        end
    end
end

reaper.UpdateArrange()

-- 结束撤销块
reaper.Undo_EndBlock("Process items in time selection", -1)