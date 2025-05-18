-- 获取时间选区
local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

-- 检查是否有时间选区
if start_time == end_time then
    reaper.MB("无时间选区，请先设置时间选区", "错误", 0)
    return
end

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

-- 检查时间选区下是否有 region 或 mark
local has_regions_marks = false
local region_count = reaper.CountProjectMarkers(0)
for i = 0, region_count - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers3(0, i)
    if isrgn then
        if pos < end_time and rgnend > start_time then
            has_regions_marks = true
            break
        end
    else
        if pos >= start_time and pos < end_time then
            has_regions_marks = true
            break
        end
    end
end

-- 若时间选区下无内容则停止运行并提示
if not has_items and not has_regions_marks then
    reaper.MB("时间选区下没有内容，停止运行。", "提示", 0)
    return
end

-- 删除时间选区下的所有 item
for i = item_count - 1, 0, -1 do
    local item = reaper.GetMediaItem(0, i)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if item_start < end_time and item_end > start_time then
        reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), item)
    end
end

-- 删除时间选区下的所有 region 和 mark
for i = region_count - 1, 0, -1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers3(0, i)
    if isrgn then
        if pos < end_time and rgnend > start_time then
            reaper.DeleteProjectMarker(0, markrgnindexnumber, isrgn)
        end
    else
        if pos >= start_time and pos < end_time then
            reaper.DeleteProjectMarker(0, markrgnindexnumber, isrgn)
        end
    end
end

reaper.MB("时间选区下的所有内容已删除。", "提示", 0)

-- 删除时间选区
reaper.GetSet_LoopTimeRange(true, false, 0, 0, true)

reaper.UpdateArrange()
    