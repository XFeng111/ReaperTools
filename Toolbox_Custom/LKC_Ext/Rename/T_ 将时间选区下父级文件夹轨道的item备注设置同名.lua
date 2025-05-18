-- 获取当前时间选区
start_time, end_time = reaper.GetSet_LoopTimeRange(0, 0, 0, 0, 0)

-- 检查是否有时间选区
if start_time == end_time then
    reaper.ShowMessageBox("请先设置时间选区", "错误", 0)
    return
end

-- 获取所有轨道数量
track_count = reaper.CountTracks(0)

-- 遍历所有轨道
for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    -- 检查轨道是否为文件夹轨道
    local is_folder = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") > 0
    if is_folder then
        -- 获取文件夹轨道名称
        local retval, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        -- 获取轨道上的 item 数量
        local item_count = reaper.CountTrackMediaItems(track)
        local item_index = 1
        for j = 0, item_count - 1 do
            local item = reaper.GetTrackMediaItem(track, j)
            -- 获取 item 的起始和结束时间
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            -- 检查 item 是否在时间选区范围内
            if item_start < end_time and item_end > start_time then
                -- 生成备注信息，在前面添加 "@" 字符
                local remark = "@" .. track_name .. string.format("_%02d", item_index)
                -- 设置 item 的备注
                reaper.GetSetMediaItemInfo_String(item, "P_NOTES", remark, true)
                item_index = item_index + 1
            end
        end
    end
end

reaper.UpdateArrange()    