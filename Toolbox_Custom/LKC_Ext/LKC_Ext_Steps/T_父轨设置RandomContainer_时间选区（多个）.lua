-- 定义一个函数来获取轨道的实际时间范围
local function getTrackTimeRange(track)
    local track_start = math.huge
    local track_end = -math.huge
    local num_items = reaper.CountTrackMediaItems(track)
    for j = 0, num_items - 1 do
        local item = reaper.GetTrackMediaItem(track, j)
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = item_start + item_len
        track_start = math.min(track_start, item_start)
        track_end = math.max(track_end, item_end)
    end
    return track_start, track_end
end

-- 定义一个函数来检查轨道是否已设置为 Random container
local function isTrackSetToRandomContainer(track)
    local fx_count = reaper.TrackFX_GetCount(track)
    for j = 0, fx_count - 1 do
        local fx_name = ""
        local _, fx_name = reaper.TrackFX_GetFXName(track, j, fx_name, 256)
        if fx_name:find("LKC Random container") then
            return true
        end
    end
    return false
end

-- 开始撤销块
reaper.Undo_BeginBlock()

-- 获取当前项目
local proj = 0

-- 获取时间选区的起始和结束位置
local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

-- 检测是否存在时间选区
if start_time == end_time then
    reaper.ShowMessageBox("没有设置时间选区，请先设置时间选区。", "提示", 0)
    -- 结束撤销块
    reaper.Undo_EndBlock("检测时间选区失败", -1)
    return
end

-- 查找 LKC Random container 对应的动作 ID
local action_id = reaper.NamedCommandLookup("_RS2336fca61005e662df6db3198d8dffa096aff3a5")
if action_id == 0 then
    reaper.ShowMessageBox("未找到 LKC Random container 对应的动作 ID，请检查。", "提示", 0)
    -- 结束撤销块
    reaper.Undo_EndBlock("未找到动作 ID", -1)
    return
end

-- 检查框选时间选区范围下是否存在符合条件的父级文件夹轨道
local has_valid_folder_tracks = false
local num_tracks = reaper.CountTracks(proj)
local folder_tracks_to_process = {}

for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(proj, i)
    local is_folder = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") > 0
    if is_folder then
        local track_start, track_end = getTrackTimeRange(track)
        if track_start < end_time and track_end > start_time then
            local num_items = reaper.CountTrackMediaItems(track)
            if num_items > 1 and not isTrackSetToRandomContainer(track) then
                has_valid_folder_tracks = true
                table.insert(folder_tracks_to_process, track)
            end
        end
    end
end

if not has_valid_folder_tracks then
    reaper.ShowMessageBox("框选时间选区范围下没有符合条件（有多个 item 且未设置）的父级文件夹轨道。", "提示", 0)
    -- 结束撤销块
    reaper.Undo_EndBlock("检测无符合条件文件夹轨道", -1)
    return
end

-- 遍历所有符合条件的父级文件夹轨道并设置为 Random container
for _, track in ipairs(folder_tracks_to_process) do
    reaper.SetOnlyTrackSelected(track)
    reaper.Main_OnCommand(action_id, 0)
end

reaper.UpdateArrange()

-- 结束撤销块
reaper.Undo_EndBlock("设置框选时间选区下符合条件的父级文件夹轨道为 Random container", -1)