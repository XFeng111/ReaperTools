-- 获取当前项目
local project = 0

-- 开始撤销块
reaper.Undo_BeginBlock()

-- 获取时间选区的起始和结束时间
local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

-- 检查是否有时间选区
if start_time == end_time then
    reaper.ShowMessageBox("没有设置时间选区，请设置时间选区后再运行脚本。", "提示", 0)
    reaper.Undo_EndBlock("清理项目名称尾缀（无有效时间选区）", -1)
    return
end

local has_item_in_range = false
local has_extension = false

-- 遍历时间选区下的所有 item
for i = 0, reaper.CountSelectedMediaItems(project) - 1 do
    local item = reaper.GetSelectedMediaItem(project, i)
    local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local end_pos = position + length

    -- 检查 item 是否在时间选区范围内
    if position < end_time and end_pos > start_time then
        has_item_in_range = true
        -- 获取 item 的名称
        local take = reaper.GetActiveTake(item)
        if take then
            local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            -- 检查名称是否有尾缀
            if name:find("%.[^.]+$") then
                has_extension = true
                -- 删除名称中的文件类型
                local new_name = name:gsub("%.[^.]+$", "")
                -- 更新 item 的名称
                reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
            end
        end
    end
end

-- 检查时间选区下是否有 item
if not has_item_in_range then
    reaper.ShowMessageBox("时间选区下没有找到项目，请调整时间选区或选择项目。", "提示", 0)
    reaper.Undo_EndBlock("清理项目名称尾缀（时间选区无项目）", -1)
    return
end

-- 检查是否有带尾缀的 item 名称
if not has_extension then
    reaper.ShowMessageBox("时间选区下的项目名称没有尾缀，无需处理。", "提示", 0)
    reaper.Undo_EndBlock("清理项目名称尾缀（无带尾缀名称）", -1)
    return
end

-- 删除时间选区
reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)

-- 更新项目
reaper.UpdateArrange()

-- 结束撤销块
reaper.Undo_EndBlock("清理项目名称尾缀", -1)    