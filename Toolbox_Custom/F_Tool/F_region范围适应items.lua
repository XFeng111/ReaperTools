-- 调整Region的起始和结束边界，使其与区域内Item保持用户自定义的距离
function Region_fit_items()
    -- 询问用户希望保持的距离（秒）
    local retval, user_input = reaper.GetUserInputs("设置距离", 2, 
        "起始距离(秒):,结束距离(秒):", 
        "0.1,0.1")
    
    -- 如果用户取消输入，则退出
    if not retval then return end
    
    -- 分割用户输入
    local start_dist_str, end_dist_str = user_input:match("([^,]+),([^,]+)")
    local start_distance = tonumber(start_dist_str)
    local end_distance = tonumber(end_dist_str)
    
    -- 验证输入
    if not start_distance or not end_distance or start_distance < 0 or end_distance < 0 then
        reaper.ShowMessageBox("请输入有效的非负数字", "输入错误", 0)
        return
    end
    
    -- 获取当前时间选区
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    -- 如果没有时间选区，则处理整个项目
    if start_time == end_time then
        start_time = 0
        end_time = reaper.GetProjectLength(0)
    end
    
    -- 获取项目中的标记和region数量
    local marker_count = reaper.CountProjectMarkers(0)
    
    -- 遍历所有标记和region
    for i = 0, marker_count - 1 do
        local _, is_region, region_start, region_end, region_name, marker_id = reaper.EnumProjectMarkers(i)
        
        -- 只处理region，并且该region与时间选区有重叠
        if is_region and not (region_end <= start_time or region_start >= end_time) then
            -- 找出该region内所有item的最早和最晚位置
            local earliest_item_start = nil
            local latest_item_end = nil
            local item_count = reaper.CountMediaItems(0)
            
            -- 遍历所有item，找到区域内的item
            for j = 0, item_count - 1 do
                local item = reaper.GetMediaItem(0, j)
                local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                
                -- 检查item是否在当前region内
                if item_start < region_end and item_end > region_start then
                    if earliest_item_start == nil or item_start < earliest_item_start then
                        earliest_item_start = item_start
                    end
                    if latest_item_end == nil or item_end > latest_item_end then
                        latest_item_end = item_end
                    end
                end
            end
            
            -- 如果找到了item
            if earliest_item_start ~= nil and latest_item_end ~= nil then
                -- 计算期望的region新边界（使用用户输入的距离）
                local new_region_start = earliest_item_start - start_distance
                local new_region_end = latest_item_end + end_distance
                
                -- 只在需要时调整region边界（考虑浮点精度）
                if math.abs(new_region_start - region_start) > 0.001 or 
                   math.abs(new_region_end - region_end) > 0.001 then
                    
                    -- 调整region边界
                    reaper.SetProjectMarker(marker_id, true, new_region_start, new_region_end, region_name)
                end
            end
        end
    end
    
    -- 更新视图
    reaper.UpdateArrange()
end

-- 开始撤销块
reaper.Undo_BeginBlock()

-- 运行主函数
Region_fit_items()

-- 结束撤销块
reaper.Undo_EndBlock("Adjust region boundaries to fit items", -1)



