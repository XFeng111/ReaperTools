-- 存储选中区域的时间范围
local selected_regions = {}

-- 遍历所有项目标记，找出选中的区域
local marker_count = reaper.CountProjectMarkers(0)
for i = 0, marker_count - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(0, i)
    if isrgn then
        -- 使用白色（0xFFFFFF）标记选中状态
        if (color & 0xFFFFFF) == 0xFFFFFF then
            table.insert(selected_regions, {start = pos, finish = rgnend, index = markrgnindexnumber})
        end
    end
end

-- 如果没有选中的区域，给出提示并退出脚本
if #selected_regions == 0 then
    reaper.MB("没有标识区域，请标记白色区域。", "提示", 0)
    return
end

-- 遍历选中的区域
for _, region in ipairs(selected_regions) do
    local start_time = region.start
    local end_time = region.finish
    local markrgnindexnumber = region.index

    -- 将光标移动到区域起始处
    reaper.SetEditCurPos(start_time, false, false)

    -- 检查时间选区下是否有 item
    local has_items = false
    local item_count = reaper.CountMediaItems(0)
    for i = 0, item_count - 1 do
        local item = reaper.GetMediaItem(0, i)
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_start < end_time and item_end > start_time then
            has_items = true
            break
        end
    end

    -- 检查时间选区下是否有 mark
    local has_marks = false
    for i = 0, marker_count - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers3(0, i)
        if not isrgn and pos >= start_time and pos < end_time then
            has_marks = true
            break
        end
    end

    if has_items or has_marks then
        -- 删除时间选区下的所有 item
        for i = item_count - 1, 0, -1 do
            local item = reaper.GetMediaItem(0, i)
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            if item_start < end_time and item_end > start_time then
                reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), item)
            end
        end

        -- 删除时间选区下的所有 mark 和所选 region
        for i = marker_count - 1, 0, -1 do
            local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(0, i)
            if (not isrgn and pos >= start_time and pos < end_time) or
               (isrgn and pos == start_time and rgnend == end_time and (color & 0xFFFFFF) == 0xFFFFFF) then
                reaper.DeleteProjectMarker(0, markrgnindexnumber, isrgn)
            end
        end
    else
        -- 若时间选区下无内容则直接删除该区域
        reaper.DeleteProjectMarker(0, markrgnindexnumber, true)
    end
end

reaper.MB("所选区域时间选区下的所有内容已删除。", "提示", 0)
reaper.UpdateArrange()
    