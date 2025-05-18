-- 检查是否有框选时间选区
function has_time_selection()
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    return start_time < end_time
end

-- 获取所选时间范围内的所有项目
function get_selected_items_in_time_range()
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local num_items = reaper.CountMediaItems(0)
    local selected_items = {}
    for i = 0, num_items - 1 do
        local item = reaper.GetMediaItem(0, i)
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_start < end_time and item_end > start_time then
            table.insert(selected_items, item)
        end
    end
    return selected_items
end

-- 处理轨道名称，忽略末尾的 _d.wav
function process_track_name(name)
    if name then
        return string.gsub(name, "(_%d+)%.wav$", "")
    end
    return "Unnamed Track"
end

-- 主函数
function main()
    if not has_time_selection() then
        reaper.ShowMessageBox("请先框选时间选区。", "提示", 0)
        return
    end

    local items = get_selected_items_in_time_range()
    local track_items = {}

    -- 按轨道对项目进行分组
    for _, item in ipairs(items) do
        local track = reaper.GetMediaItem_Track(item)
        if not track_items[track] then
            track_items[track] = {}
        end
        table.insert(track_items[track], item)
    end

    -- 处理每个轨道上的项目
    for track, items_in_track in pairs(track_items) do
        -- 对项目按起始位置排序
        table.sort(items_in_track, function(a, b)
            return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
        end)

        -- 间隔项目 1 秒
        local position = reaper.GetMediaItemInfo_Value(items_in_track[1], "D_POSITION")
        for _, item in ipairs(items_in_track) do
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", position)
            local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            position = position + item_length + 1
        end

        -- 获取第一个项目的名称作为轨道名称
        local first_take = reaper.GetActiveTake(items_in_track[1])
        local track_name
        if first_take then
            local success, raw_name = reaper.GetSetMediaItemTakeInfo_String(first_take, "P_NAME", "", false)
            if success then
                track_name = process_track_name(raw_name)
            else
                track_name = "Unnamed Track"
            end
        else
            track_name = "Unnamed Track"
        end
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", track_name, true)

        -- 为轨道上的所有项目创建一个总区域
        local region_start = reaper.GetMediaItemInfo_Value(items_in_track[1], "D_POSITION")
        local last_item = items_in_track[#items_in_track]
        local region_end = reaper.GetMediaItemInfo_Value(last_item, "D_POSITION") + reaper.GetMediaItemInfo_Value(last_item, "D_LENGTH")
        reaper.AddProjectMarker2(0, true, region_start, region_end, track_name, -1, 0)
    end

    reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Process items in time selection", -1)
    