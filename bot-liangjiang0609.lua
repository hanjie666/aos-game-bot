-- process: QM0gImIJwUuy49zwbXhl3YiYX9Ep_rSVprauXp8JflY

-- 初始化全局变量以存储最新的游戏状态和游戏主机进程
GameState = GameState or nil
ActionInProgress = ActionInProgress or false -- 防止代理同时执行多个操作

ActivityLogs = ActivityLogs or {}

-- 定义颜色常量用于日志输出
colorCodes = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

-- 添加日志条目
function logMessage(event, message)
  ActivityLogs[event] = ActivityLogs[event] or {}
  table.insert(ActivityLogs[event], message)
end

-- 检查玩家的距离是否在指定范围内
function isWithinDistance(x1, y1, x2, y2, distance)
  return (math.abs(x1 - x2) <= distance) and (math.abs(y1 - y2) <= distance)
end

-- 根据玩家的距离和能量决定下一步动作
-- 如果有玩家在范围内则攻击，否则随机移动
-- {
--   "QM0gImIJwUuy49zwbXhl3YiYX9Ep_rSVprauXp8JflY": {
--       "x": 27,
--       "y": 11,
--       "energy": 93,
--       "health": 100
--   },
--   "QoJqFnqB-9mDPFeKhxld0PBGJPzbE4KHNI8aJ3JOAJY": {
--       "x": 16,
--       "y": 24,
--       "energy": 93,
--       "health": 100
--   }
-- }
function determineNextAction()
  local currentPlayer = GameState.Players[ao.id]
  local enemyNearby = false
  local trackHealth = currentPlayer.energy
  -- 检查 currentPlayer 是否为空
  if currentPlayer == nil then
    print("当前玩家不存在")
    return
  end
  print("我的血量：" .. currentPlayer.health)
  for playerID, playerState in pairs(GameState.Players) do
    if playerID ~= ao.id and isWithinDistance(currentPlayer.x, currentPlayer.y, playerState.x, playerState.y, 3) then
      enemyNearby = true
      if currentPlayer.energy >= playerState.health then
        trackHealth = playerState.health
      end
      if currentPlayer.energy < playerState.health then
        trackHealth = currentPlayer.energy
      end
      break
    end
  end

  if currentPlayer.energy > 20 and enemyNearby then
    print(colorCodes.red .. "敌人在范围内，发起攻击，干他嘿嘿嘿" .. colorCodes.reset)
    ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(trackHealth)})
  else
    print(colorCodes.red .. "没有敌人在范围内或能量不足，随机移动。" .. colorCodes.reset)
    local directions = {"Up", "Left", "Down", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
    local chosenDirection = directions[math.random(#directions)]
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = chosenDirection})
  end
  ActionInProgress = false -- 重置标志
end

-- 打印游戏公告并处理游戏状态更新
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (message)
    if message.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (message.Event == "Tick" or message.Event == "Started-Game") and not ActionInProgress then
      ActionInProgress = true
      ao.send({Target = Game, Action = "GetGameState"})
    elseif ActionInProgress then
      print("之前的操作仍在进行中，跳过。。。。。。")
    end
    print(colorCodes.green .. message.Event .. ": " .. message.Data .. colorCodes.reset)
  end
)

-- 在Tick事件时触发游戏状态更新
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not ActionInProgress then
      ActionInProgress = true
      print(colorCodes.gray .. "获取游戏状态..." .. colorCodes.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("之前的操作仍在进行中，跳过。。。。")
    end
  end
)

-- 等待期开始时自动确认付款
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (message)
    print("支付费用")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
    print("支付成功")
  end
)

-- 接收并更新游戏状态
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (message)
    local json = require("json")
    GameState = json.decode(message.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("游戏状态已更新。使用 'GameState' 查看详细信息。")
  end
)

-- 根据最新的游戏状态决策下一步动作
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if GameState.GameMode ~= "Playing" then
      ActionInProgress = false
      return
    end
    print("决定下一步操作。")
    determineNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- 在被攻击时自动反击
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (message)
    if not ActionInProgress then
      ActionInProgress = true
      local energy = GameState.Players[ao.id].energy
      if energy == nil then
        print(colorCodes.red .. "无法读取能量。" .. colorCodes.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "无法读取能量。"})
      elseif energy == 0 then
        print(colorCodes.red .. "玩家能量不足。" .. colorCodes.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "能量不足。"})
      else
        print(colorCodes.red .. "反击。" .. colorCodes.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(energy)})
      end
      ActionInProgress = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("之前的操作仍在进行中，跳过。")
    end
  end
)
