local function GetBladeHits()
    local targets = {}
    local function GetDistance(v)
        return (v.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
    end
    
    for _, part in pairs({
        game.Workspace.Enemies,
        game.Workspace.Characters
    }) do
        for _, v in pairs(part:GetChildren()) do
            if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Head") and v:FindFirstChild("Humanoid") then
                if GetDistance(v.HumanoidRootPart) < 60 then
                    table.insert(targets, v)
                end
            end
        end
    end

    return targets
end

local function AttackAll()
    local player = game.Players.LocalPlayer
    local character = player.Character
    if not character then
        return
    end

    local equippedWeapon = character:FindFirstChild("EquippedWeapon")
    if not equippedWeapon then
        return
    end


    local enemies = GetBladeHits()
    if # enemies > 0 then
        local netModule = game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Net")
        netModule:WaitForChild("RE/RegisterAttack"):FireServer(- math.huge)
        
        local args = {
            nil,
            {}
        }
        for i, v in pairs(enemies) do
            if not args[1] then
                args[1] = v.Head
            end
            args[2][i] = {
                v,
                v.HumanoidRootPart
            }
        end
        
        netModule:WaitForChild("RE/RegisterHit"):FireServer(unpack(args))
    end
end

spawn(function()
    while task.wait() do
        AttackAll()
    end
end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
if not player.Team then
    if getgenv().Team == "Marines" then
        ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", "Marines")
    elseif getgenv().Team == "Pirates" then
        ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", "Pirates")
    end
    repeat
        task.wait(1)
        local chooseTeam = playerGui:FindFirstChild("ChooseTeam", true)
        local uiController = playerGui:FindFirstChild("UIController", true)
        if chooseTeam and chooseTeam.Visible and uiController then
            for _, v in pairs(getgc(true)) do
                if type(v) == "function" and getfenv(v).script == uiController then
                    local constant = getconstants(v)
                    pcall(function()
                        if (constant[1] == "Pirates" or constant[1] == "Marines") and # constant == 1 then
                            if constant[1] == getgenv().Team then
                                v(getgenv().Team)
                            end
                        end
                    end)
                end
            end
        end
    until player.Team
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Net = Modules:WaitForChild("Net")
local RegisterAttack = Net:WaitForChild("RE/RegisterAttack")
local RegisterHit = Net:WaitForChild("RE/RegisterHit")
local ShootGunEvent = Net:WaitForChild("RE/ShootGunEvent")
local GunValidator = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Validator2")

local Config = {
    AttackDistance = 65,
    AttackMobs = true,
    AttackPlayers = true,
    AttackCooldown = 0.2,
    ComboResetTime = 0.3,
    MaxCombo = 4,
    HitboxLimbs = {
        "RightLowerArm",
        "RightUpperArm",
        "LeftLowerArm",
        "LeftUpperArm",
        "RightHand",
        "LeftHand"
    },
    AutoClickEnabled = true
}

local FastAttack = {}
FastAttack.__index = FastAttack

function FastAttack.new()
    local self = setmetatable({
        Debounce = 0,
        ComboDebounce = 0,
        ShootDebounce = 0,
        M1Combo = 0,
        EnemyRootPart = nil,
        Connections = {},
        Overheat = {
            Dragonstorm = {
                MaxOverheat = 3,
                Cooldown = 0,
                TotalOverheat = 0,
                Distance = 350,
                Shooting = false
            }
        },
        ShootsPerTarget = {
            ["Dual Flintlock"] = 2
        },
        SpecialShoots = {
            ["Skull Guitar"] = "TAP",
            ["Bazooka"] = "Position",
            ["Cannon"] = "Position",
            ["Dragonstorm"] = "Overheat"
        }
    }, FastAttack)
    
    pcall(function()
        self.CombatFlags = require(Modules.Flags).COMBAT_REMOTE_THREAD
        self.ShootFunction = getupvalue(require(ReplicatedStorage.Controllers.CombatController).Attack, 9)
        local LocalScript = Player:WaitForChild("PlayerScripts"):FindFirstChildOfClass("LocalScript")
        if LocalScript and getsenv then
            self.HitFunction = getsenv(LocalScript)._G.SendHitsToServer
        end
    end)
    
    return self
end

function FastAttack:IsEntityAlive(entity)
    local humanoid = entity and entity:FindFirstChild("Humanoid")
    return humanoid and humanoid.Health > 0
end

function FastAttack:CheckStun(Character, Humanoid, ToolTip)
    local Stun = Character:FindFirstChild("Stun")
    local Busy = Character:FindFirstChild("Busy")
    if Humanoid.Sit and (ToolTip == "Sword" or ToolTip == "Melee" or ToolTip == "Blox Fruit") then
        return false
    elseif Stun and Stun.Value > 0 or Busy and Busy.Value then
        return false
    end
    return true
end

function FastAttack:GetBladeHits(Character, Distance)
    local Position = Character:GetPivot().Position
    local BladeHits = {}
    Distance = Distance or Config.AttackDistance
    
    local function ProcessTargets(Folder, CanAttack)
        for _, Enemy in ipairs(Folder:GetChildren()) do
            if Enemy ~= Character and self:IsEntityAlive(Enemy) then
                local BasePart = Enemy:FindFirstChild(Config.HitboxLimbs[math.random(# Config.HitboxLimbs)]) or Enemy:FindFirstChild("HumanoidRootPart")
                if BasePart and (Position - BasePart.Position).Magnitude <= Distance then
                    if not self.EnemyRootPart then
                        self.EnemyRootPart = BasePart
                    else
                        table.insert(BladeHits, {
                            Enemy,
                            BasePart
                        })
                    end
                end
            end
        end
    end
    
    if Config.AttackMobs then
        ProcessTargets(Workspace.Enemies)
    end
    if Config.AttackPlayers then
        ProcessTargets(Workspace.Characters, true)
    end
    
    return BladeHits
end

function FastAttack:GetClosestEnemy(Character, Distance)
    local BladeHits = self:GetBladeHits(Character, Distance)
    local Closest, MinDistance = nil, math.huge
    
    for _, Hit in ipairs(BladeHits) do
        local Magnitude = (Character:GetPivot().Position - Hit[2].Position).Magnitude
        if Magnitude < MinDistance then
            MinDistance = Magnitude
            Closest = Hit[2]
        end
    end
    return Closest
end

function FastAttack:GetCombo()
    local Combo = (tick() - self.ComboDebounce) <= Config.ComboResetTime and self.M1Combo or 0
    Combo = Combo >= Config.MaxCombo and 1 or Combo + 1
    self.ComboDebounce = tick()
    self.M1Combo = Combo
    return Combo
end

function FastAttack:ShootInTarget(TargetPosition)
    local Character = Player.Character
    if not self:IsEntityAlive(Character) then
        return
    end
    
    local Equipped = Character:FindFirstChildOfClass("Tool")
    if not Equipped or Equipped.ToolTip ~= "Gun" then
        return
    end
    
    local Cooldown = Equipped:FindFirstChild("Cooldown") and Equipped.Cooldown.Value or 0.3
    if (tick() - self.ShootDebounce) < Cooldown then
        return
    end
    
    local ShootType = self.SpecialShoots[Equipped.Name] or "Normal"
    if ShootType == "Position" or (ShootType == "TAP" and Equipped:FindFirstChild("RemoteEvent")) then
        Equipped:SetAttribute("LocalTotalShots", (Equipped:GetAttribute("LocalTotalShots") or 0) + 1)
        GunValidator:FireServer(self:GetValidator2())
        
        if ShootType == "TAP" then
            Equipped.RemoteEvent:FireServer("TAP", TargetPosition)
        else
            ShootGunEvent:FireServer(TargetPosition)
        end
        self.ShootDebounce = tick()
    else
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        self.ShootDebounce = tick()
    end
end

function FastAttack:GetValidator2()
    local v1 = getupvalue(self.ShootFunction, 15)
    local v2 = getupvalue(self.ShootFunction, 13)
    local v3 = getupvalue(self.ShootFunction, 16)
    local v4 = getupvalue(self.ShootFunction, 17)
    local v5 = getupvalue(self.ShootFunction, 14)
    local v6 = getupvalue(self.ShootFunction, 12)
    local v7 = getupvalue(self.ShootFunction, 18)
    
    local v8 = v6 * v2
    local v9 = (v5 * v2 + v6 * v1) % v3
    v9 = (v9 * v3 + v8) % v4
    v5 = math.floor(v9 / v3)
    v6 = v9 - v5 * v3
    v7 = v7 + 1
    
    setupvalue(self.ShootFunction, 15, v1)
    setupvalue(self.ShootFunction, 13, v2)
    setupvalue(self.ShootFunction, 16, v3)
    setupvalue(self.ShootFunction, 17, v4)
    setupvalue(self.ShootFunction, 14, v5)
    setupvalue(self.ShootFunction, 12, v6)
    setupvalue(self.ShootFunction, 18, v7)
    
    return math.floor(v9 / v4 * 16777215), v7
end

function FastAttack:UseNormalClick(Character, Humanoid, Cooldown)
    self.EnemyRootPart = nil
    local BladeHits = self:GetBladeHits(Character)
    
    if self.EnemyRootPart then
        RegisterAttack:FireServer(Cooldown)
        if self.CombatFlags and self.HitFunction then
            self.HitFunction(self.EnemyRootPart, BladeHits)
        else
            RegisterHit:FireServer(self.EnemyRootPart, BladeHits)
        end
    end
end

function FastAttack:UseFruitM1(Character, Equipped, Combo)
    local Targets = self:GetBladeHits(Character)
    if not Targets[1] then
        return
    end
    
    local Direction = (Targets[1][2].Position - Character:GetPivot().Position).Unit
    Equipped.LeftClickRemote:FireServer(Direction, Combo)
end

function FastAttack:Attack()
    if not Config.AutoClickEnabled or (tick() - self.Debounce) < Config.AttackCooldown then
        return
    end
    local Character = Player.Character
    if not Character or not self:IsEntityAlive(Character) then
        return
    end
    
    local Humanoid = Character.Humanoid
    local Equipped = Character:FindFirstChildOfClass("Tool")
    if not Equipped then
        return
    end
    
    local ToolTip = Equipped.ToolTip
    if not table.find({
        "Melee",
        "Blox Fruit",
        "Sword",
        "Gun"
    }, ToolTip) then
        return
    end
    
    local Cooldown = Equipped:FindFirstChild("Cooldown") and Equipped.Cooldown.Value or Config.AttackCooldown
    if not self:CheckStun(Character, Humanoid, ToolTip) then
        return
    end
    
    local Combo = self:GetCombo()
    Cooldown = Cooldown + (Combo >= Config.MaxCombo and 0.05 or 0)
    self.Debounce = Combo >= Config.MaxCombo and ToolTip ~= "Gun" and (tick() + 0.05) or tick()
    
    if ToolTip == "Blox Fruit" and Equipped:FindFirstChild("LeftClickRemote") then
        self:UseFruitM1(Character, Equipped, Combo)
    elseif ToolTip == "Gun" then
        local Target = self:GetClosestEnemy(Character, 120)
        if Target then
            self:ShootInTarget(Target.Position)
        end
    else
        self:UseNormalClick(Character, Humanoid, Cooldown)
    end
end

local AttackInstance = FastAttack.new()
table.insert(AttackInstance.Connections, RunService.Stepped:Connect(function()
    AttackInstance:Attack()
end))

for _, v in pairs(getgc(true)) do
    if typeof(v) == "function" and iscclosure(v) then
        local name = debug.getinfo(v).name
        if name == "Attack" or name == "attack" or name == "RegisterHit" then
            hookfunction(v, function(...)
                AttackInstance:Attack()
                return v(...)
            end)
        end
    end
end
---Fast 2 ---
local Modules = game.ReplicatedStorage.Modules
local Net = Modules.Net
local Register_Hit, Register_Attack = Net:WaitForChild("RE/RegisterHit"), Net:WaitForChild("RE/RegisterAttack")
local Funcs = {}
function GetAllBladeHits()
    bladehits = {}
    for _, v in pairs(workspace.Enemies:GetChildren()) do
        if v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and (v.HumanoidRootPart.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 65 then
            table.insert(bladehits, v)
        end
    end
    return bladehits
end
function Getplayerhit()
    bladehits = {}
    for _, v in pairs(workspace.Characters:GetChildren()) do
        if v.Name ~= game.Players.LocalPlayer.Name and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and (v.HumanoidRootPart.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 65 then
            table.insert(bladehits, v)
        end
    end
    return bladehits
end
function Funcs:Attack()
    local bladehits = {}
    for r, v in pairs(GetAllBladeHits()) do
        table.insert(bladehits, v)
    end
    for r, v in pairs(Getplayerhit()) do
        table.insert(bladehits, v)
    end
    if # bladehits == 0 then
        return
    end
    local args = {
        [1] = nil;
        [2] = {},
        [4] = "078da341"
    }
    for r, v in pairs(bladehits) do
        Register_Attack:FireServer(0)
        if not args[1] then
            args[1] = v.Head
        end
        args[2][r] = {
            [1] = v,
            [2] = v.HumanoidRootPart
        }
    end
    Register_Hit:FireServer(unpack(args))
end

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/giaotrinhhoc/Giao-Trinh-Hoc-Ngoai-Ngu-Cua-Hoc-Sinh/refs/heads/main/FluentTrau"))();
local Window = Fluent:CreateWindow({Title="Ldt Hub",SubTitle=Le Duc Tho"",TabWidth=160,Theme="Dark",Acrylic=false,Size=UDim2.fromOffset(500, 320),MinimizeKey=Enum.KeyCode.End});
local Tabs = {Home=Window:AddTab({Title="Thông Tin"}),
    Main=Window:AddTab({Title="Chung"}),
    Sea=Window:AddTab({Title="Sự Kiện"}),
    New=Window:AddTab({Title="Sự Kiện Mới"}),
    ITM=Window:AddTab({Title="Vật Phẩm"}),
    Setting=Window:AddTab({Title="Cài Đặt"}),
    Status=Window:AddTab({Title="Máy Chủ"}),
    Stats=Window:AddTab({Title="Chỉ Số"}),
    Player=Window:AddTab({Title="Người Chơi"}),
    Teleport=Window:AddTab({Title="Dịch Chuyển"}),
    Visual=Window:AddTab({Title="Giả"}),
    Fruit=Window:AddTab({Title="Trái"}),
    Raid=Window:AddTab({Title="Tập Kích"}),
    Race=Window:AddTab({Title="Tộc"}),
    Shop=Window:AddTab({Title="Cửa Hàng"}),
    Misc=Window:AddTab({Title="Khác"})
};
local Options = Fluent.Options;
local id = game.PlaceId;
if (id == 2753915549) then
	Sea1 = true;
elseif (id == 4442272183) then
	Sea2 = true;
elseif (id == 7449423635) then
	Sea3 = true;
else
	game:Shutdown();
end
game:GetService("Players").LocalPlayer.Idled:connect(function()
	game:GetService("VirtualUser"):Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame);
	wait();
	game:GetService("VirtualUser"):Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame);
end);
Sea1 = false;
Sea2 = false;
Sea3 = false;
local placeId = game.PlaceId;
if (placeId == 2753915549) then
	Sea1 = true;
elseif (placeId == 4442272183) then
	Sea2 = true;
elseif (placeId == 7449423635) then
	Sea3 = true;
end
function CheckQuest() 
    MyLevel = game:GetService("Players").LocalPlayer.Data.Level.Value
    if Sea1 then
        if MyLevel >= 1 and MyLevel <= 9 then
            Mon = "Bandit"
            LevelQuest = 1
            NameQuest = "BanditQuest1"
            NameMon = "Bandit"
            CFrameQuest = CFrame.new(1059.37195, 15.4495068, 1550.4231, 0.939700544, -0, -0.341998369, 0, 1, -0, 0.341998369, 0, 0.939700544)
            CFrameMon = CFrame.new(1045.962646484375, 27.00250816345215, 1560.8203125)
        elseif MyLevel >= 10 and MyLevel <= 14 then
            Mon = "Monkey"
            LevelQuest = 1
            NameQuest = "JungleQuest"
            NameMon = "Monkey"
            CFrameQuest = CFrame.new(-1598.08911, 35.5501175, 153.377838, 0, 0, 1, 0, 1, -0, -1, 0, 0)
            CFrameMon = CFrame.new(-1448.51806640625, 67.85301208496094, 11.46579647064209)
        elseif MyLevel >= 15 and MyLevel <= 29 then
            Mon = "Gorilla"
            LevelQuest = 2
            NameQuest = "JungleQuest"
            NameMon = "Gorilla"
            CFrameQuest = CFrame.new(-1598.08911, 35.5501175, 153.377838, 0, 0, 1, 0, 1, -0, -1, 0, 0)
            CFrameMon = CFrame.new(-1129.8836669921875, 40.46354675292969, -525.4237060546875)
        elseif MyLevel >= 30 and MyLevel <= 39 then
            Mon = "Pirate"
            LevelQuest = 1
            NameQuest = "BuggyQuest1"
            NameMon = "Pirate"
            CFrameQuest = CFrame.new(-1141.07483, 4.10001802, 3831.5498, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627)
            CFrameMon = CFrame.new(-1103.513427734375, 13.752052307128906, 3896.091064453125)
        elseif MyLevel >= 40 and MyLevel <= 59 then
            Mon = "Brute"
            LevelQuest = 2
            NameQuest = "BuggyQuest1"
            NameMon = "Brute"
            CFrameQuest = CFrame.new(-1141.07483, 4.10001802, 3831.5498, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627)
            CFrameMon = CFrame.new(-1140.083740234375, 14.809885025024414, 4322.92138671875)
        elseif MyLevel >= 60 and MyLevel <= 74 then
            Mon = "Desert Bandit"
            LevelQuest = 1
            NameQuest = "DesertQuest"
            NameMon = "Desert Bandit"
            CFrameQuest = CFrame.new(894.488647, 5.14000702, 4392.43359, 0.819155693, -0, -0.573571265, 0, 1, -0, 0.573571265, 0, 0.819155693)
            CFrameMon = CFrame.new(924.7998046875, 6.44867467880249, 4481.5859375)
        elseif MyLevel >= 75 and MyLevel <= 89 then
            Mon = "Desert Officer"
            LevelQuest = 2
            NameQuest = "DesertQuest"
            NameMon = "Desert Officer"
            CFrameQuest = CFrame.new(894.488647, 5.14000702, 4392.43359, 0.819155693, -0, -0.573571265, 0, 1, -0, 0.573571265, 0, 0.819155693)
            CFrameMon = CFrame.new(1608.2822265625, 8.614224433898926, 4371.00732421875)
        elseif MyLevel >= 90 and MyLevel <= 99 then
            Mon = "Snow Bandit"
            LevelQuest = 1
            NameQuest = "SnowQuest"
            NameMon = "Snow Bandit"
            CFrameQuest = CFrame.new(1389.74451, 88.1519318, -1298.90796, -0.342042685, 0, 0.939684391, 0, 1, 0, -0.939684391, 0, -0.342042685)
            CFrameMon = CFrame.new(1354.347900390625, 87.27277374267578, -1393.946533203125)
        elseif MyLevel >= 100 and MyLevel <= 119 then
            Mon = "Snowman"
            LevelQuest = 2
            NameQuest = "SnowQuest"
            NameMon = "Snowman"
            CFrameQuest = CFrame.new(1389.74451, 88.1519318, -1298.90796, -0.342042685, 0, 0.939684391, 0, 1, 0, -0.939684391, 0, -0.342042685)
            CFrameMon = CFrame.new(1201.6412353515625, 144.57958984375, -1550.0670166015625)
        elseif MyLevel >= 120 and MyLevel <= 149 then
            Mon = "Chief Petty Officer"
            LevelQuest = 1
            NameQuest = "MarineQuest2"
            NameMon = "Chief Petty Officer"
            CFrameQuest = CFrame.new(-5039.58643, 27.3500385, 4324.68018, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            CFrameMon = CFrame.new(-4881.23095703125, 22.65204429626465, 4273.75244140625)
        elseif MyLevel >= 150 and MyLevel <= 174 then
            Mon = "Sky Bandit"
            LevelQuest = 1
            NameQuest = "SkyQuest"
            NameMon = "Sky Bandit"
            CFrameQuest = CFrame.new(-4839.53027, 716.368591, -2619.44165, 0.866007268, 0, 0.500031412, 0, 1, 0, -0.500031412, 0, 0.866007268)
            CFrameMon = CFrame.new(-4953.20703125, 295.74420166015625, -2899.22900390625)
        elseif MyLevel >= 175 and MyLevel <= 189 then
            Mon = "Dark Master"
            LevelQuest = 2
            NameQuest = "SkyQuest"
            NameMon = "Dark Master"
            CFrameQuest = CFrame.new(-4839.53027, 716.368591, -2619.44165, 0.866007268, 0, 0.500031412, 0, 1, 0, -0.500031412, 0, 0.866007268)
            CFrameMon = CFrame.new(-5259.8447265625, 391.3976745605469, -2229.035400390625)
        elseif MyLevel >= 190 and MyLevel <= 209 then
            Mon = "Prisoner"
            LevelQuest = 1
            NameQuest = "PrisonerQuest"
            NameMon = "Prisoner"
            CFrameQuest = CFrame.new(5308.93115, 1.65517521, 475.120514, -0.0894274712, -5.00292918e-09, -0.995993316, 1.60817859e-09, 1, -5.16744869e-09, 0.995993316, -2.06384709e-09, -0.0894274712)
            CFrameMon = CFrame.new(5098.9736328125, -0.3204058110713959, 474.2373352050781)
        elseif MyLevel >= 210 and MyLevel <= 249 then
            Mon = "Dangerous Prisoner"
            LevelQuest = 2
            NameQuest = "PrisonerQuest"
            NameMon = "Dangerous Prisoner"
            CFrameQuest = CFrame.new(5308.93115, 1.65517521, 475.120514, -0.0894274712, -5.00292918e-09, -0.995993316, 1.60817859e-09, 1, -5.16744869e-09, 0.995993316, -2.06384709e-09, -0.0894274712)
            CFrameMon = CFrame.new(5654.5634765625, 15.633401870727539, 866.2991943359375)
        elseif MyLevel >= 250 and MyLevel <= 274 then
            Mon = "Toga Warrior"
            LevelQuest = 1
            NameQuest = "ColosseumQuest"
            NameMon = "Toga Warrior"
            CFrameQuest = CFrame.new(-1580.04663, 6.35000277, -2986.47534, -0.515037298, 0, -0.857167721, 0, 1, 0, 0.857167721, 0, -0.515037298)
            CFrameMon = CFrame.new(-1820.21484375, 51.68385696411133, -2740.6650390625)
        elseif MyLevel >= 275 and MyLevel <= 299 then
            Mon = "Gladiator"
            LevelQuest = 2
            NameQuest = "ColosseumQuest"
            NameMon = "Gladiator"
            CFrameQuest = CFrame.new(-1580.04663, 6.35000277, -2986.47534, -0.515037298, 0, -0.857167721, 0, 1, 0, 0.857167721, 0, -0.515037298)
            CFrameMon = CFrame.new(-1292.838134765625, 56.380882263183594, -3339.031494140625)
        elseif MyLevel >= 300 and MyLevel <= 324 then
            Mon = "Military Soldier"
            LevelQuest = 1
            NameQuest = "MagmaQuest"
            NameMon = "Military Soldier"
            CFrameQuest = CFrame.new(-5313.37012, 10.9500084, 8515.29395, -0.499959469, 0, 0.866048813, 0, 1, 0, -0.866048813, 0, -0.499959469)
            CFrameMon = CFrame.new(-5411.16455078125, 11.081554412841797, 8454.29296875)
        elseif MyLevel >= 325 and MyLevel <= 374 then
            Mon = "Military Spy"
            LevelQuest = 2
            NameQuest = "MagmaQuest"
            NameMon = "Military Spy"
            CFrameQuest = CFrame.new(-5313.37012, 10.9500084, 8515.29395, -0.499959469, 0, 0.866048813, 0, 1, 0, -0.866048813, 0, -0.499959469)
            CFrameMon = CFrame.new(-5802.8681640625, 86.26241302490234, 8828.859375)
        elseif MyLevel >= 375 and MyLevel <= 399 then
            Mon = "Fishman Warrior"
            LevelQuest = 1
            NameQuest = "FishmanQuest"
            NameMon = "Fishman Warrior"
            CFrameQuest = CFrame.new(61122.65234375, 18.497442245483, 1569.3997802734)
            CFrameMon = CFrame.new(60878.30078125, 18.482830047607422, 1543.7574462890625)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance",Vector3.new(61163.8515625, 11.6796875, 1819.7841796875))
            end
        elseif MyLevel >= 400 and MyLevel <= 449 then
            Mon = "Fishman Commando"
            LevelQuest = 2
            NameQuest = "FishmanQuest"
            NameMon = "Fishman Commando"
            CFrameQuest = CFrame.new(61122.65234375, 18.497442245483, 1569.3997802734)
            CFrameMon = CFrame.new(61922.6328125, 18.482830047607422, 1493.934326171875)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance",Vector3.new(61163.8515625, 11.6796875, 1819.7841796875))
            end
        elseif MyLevel >= 450 and MyLevel <= 474 then
            Mon = "God's Guard"
            LevelQuest = 1
            NameQuest = "SkyExp1Quest"
            NameMon = "God's Guard"
            CFrameQuest = CFrame.new(-4721.88867, 843.874695, -1949.96643, 0.996191859, -0, -0.0871884301, 0, 1, -0, 0.0871884301, 0, 0.996191859)
            CFrameMon = CFrame.new(-4710.04296875, 845.2769775390625, -1927.3079833984375)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance",Vector3.new(-4607.82275, 872.54248, -1667.55688))
            end
        elseif MyLevel >= 475 and MyLevel <= 524 then
            Mon = "Shanda"
            LevelQuest = 2
            NameQuest = "SkyExp1Quest"
            NameMon = "Shanda"
            CFrameQuest = CFrame.new(-7859.09814, 5544.19043, -381.476196, -0.422592998, 0, 0.906319618, 0, 1, 0, -0.906319618, 0, -0.422592998)
            CFrameMon = CFrame.new(-7678.48974609375, 5566.40380859375, -497.2156066894531)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance",Vector3.new(-7894.6176757813, 5547.1416015625, -380.29119873047))
            end
        elseif MyLevel >= 525 and MyLevel <= 549 then
            Mon = "Royal Squad"
            LevelQuest = 1
            NameQuest = "SkyExp2Quest"
            NameMon = "Royal Squad"
            CFrameQuest = CFrame.new(-7906.81592, 5634.6626, -1411.99194, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            CFrameMon = CFrame.new(-7624.25244140625, 5658.13330078125, -1467.354248046875)
        elseif MyLevel >= 550 and MyLevel <= 624 then
            Mon = "Royal Soldier"
            LevelQuest = 2
            NameQuest = "SkyExp2Quest"
            NameMon = "Royal Soldier"
            CFrameQuest = CFrame.new(-7906.81592, 5634.6626, -1411.99194, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            CFrameMon = CFrame.new(-7836.75341796875, 5645.6640625, -1790.6236572265625)
        elseif MyLevel >= 625 and MyLevel <= 649 then
            Mon = "Galley Pirate"
            LevelQuest = 1
            NameQuest = "FountainQuest"
            NameMon = "Galley Pirate"
            CFrameQuest = CFrame.new(5259.81982, 37.3500175, 4050.0293, 0.087131381, 0, 0.996196866, 0, 1, 0, -0.996196866, 0, 0.087131381)
            CFrameMon = CFrame.new(5551.02197265625, 78.90135192871094, 3930.412841796875)
        elseif MyLevel >= 650 then
            Mon = "Galley Captain"
            LevelQuest = 2
            NameQuest = "FountainQuest"
            NameMon = "Galley Captain"
            CFrameQuest = CFrame.new(5259.81982, 37.3500175, 4050.0293, 0.087131381, 0, 0.996196866, 0, 1, 0, -0.996196866, 0, 0.087131381)
            CFrameMon = CFrame.new(5441.95166015625, 42.50205993652344, 4950.09375)
        end
    elseif Sea2 then
        if MyLevel >= 700 and MyLevel <= 724 then
            Mon = "Raider"
            LevelQuest = 1
            NameQuest = "Area1Quest"
            NameMon = "Raider"
            CFrameQuest = CFrame.new(-429.543518, 71.7699966, 1836.18188, -0.22495985, 0, -0.974368095, 0, 1, 0, 0.974368095, 0, -0.22495985)
            CFrameMon = CFrame.new(-728.3267211914062, 52.779319763183594, 2345.7705078125)
        elseif MyLevel >= 725 and MyLevel <= 774 then
            Mon = "Mercenary"
            LevelQuest = 2
            NameQuest = "Area1Quest"
            NameMon = "Mercenary"
            CFrameQuest = CFrame.new(-429.543518, 71.7699966, 1836.18188, -0.22495985, 0, -0.974368095, 0, 1, 0, 0.974368095, 0, -0.22495985)
            CFrameMon = CFrame.new(-1004.3244018554688, 80.15886688232422, 1424.619384765625)
        elseif MyLevel >= 775 and MyLevel <= 799 then
            Mon = "Swan Pirate"
            LevelQuest = 1
            NameQuest = "Area2Quest"
            NameMon = "Swan Pirate"
            CFrameQuest = CFrame.new(638.43811, 71.769989, 918.282898, 0.139203906, 0, 0.99026376, 0, 1, 0, -0.99026376, 0, 0.139203906)
            CFrameMon = CFrame.new(1068.664306640625, 137.61428833007812, 1322.1060791015625)
        elseif MyLevel >= 800 and MyLevel <= 874 then
            Mon = "Factory Staff"
            NameQuest = "Area2Quest"
            LevelQuest = 2
            NameMon = "Factory Staff"
            CFrameQuest = CFrame.new(632.698608, 73.1055908, 918.666321, -0.0319722369, 8.96074881e-10, -0.999488771, 1.36326533e-10, 1, 8.92172336e-10, 0.999488771, -1.07732087e-10, -0.0319722369)
            CFrameMon = CFrame.new(73.07867431640625, 81.86344146728516, -27.470672607421875)
        elseif MyLevel >= 875 and MyLevel <= 899 then
            Mon = "Marine Lieutenant"
            LevelQuest = 1
            NameQuest = "MarineQuest3"
            NameMon = "Marine Lieutenant"
            CFrameQuest = CFrame.new(-2440.79639, 71.7140732, -3216.06812, 0.866007268, 0, 0.500031412, 0, 1, 0, -0.500031412, 0, 0.866007268)
            CFrameMon = CFrame.new(-2821.372314453125, 75.89727783203125, -3070.089111328125)
        elseif MyLevel >= 900 and MyLevel <= 949 then
            Mon = "Marine Captain"
            LevelQuest = 2
            NameQuest = "MarineQuest3"
            NameMon = "Marine Captain"
            CFrameQuest = CFrame.new(-2440.79639, 71.7140732, -3216.06812, 0.866007268, 0, 0.500031412, 0, 1, 0, -0.500031412, 0, 0.866007268)
            CFrameMon = CFrame.new(-1861.2310791015625, 80.17658233642578, -3254.697509765625)
        elseif MyLevel >= 950 and MyLevel <= 974 then
            Mon = "Zombie"
            LevelQuest = 1
            NameQuest = "ZombieQuest"
            NameMon = "Zombie"
            CFrameQuest = CFrame.new(-5497.06152, 47.5923004, -795.237061, -0.29242146, 0, -0.95628953, 0, 1, 0, 0.95628953, 0, -0.29242146)
            CFrameMon = CFrame.new(-5657.77685546875, 78.96973419189453, -928.68701171875)
        elseif MyLevel >= 975 and MyLevel <= 999 then
            Mon = "Vampire"
            LevelQuest = 2
            NameQuest = "ZombieQuest"
            NameMon = "Vampire"
            CFrameQuest = CFrame.new(-5497.06152, 47.5923004, -795.237061, -0.29242146, 0, -0.95628953, 0, 1, 0, 0.95628953, 0, -0.29242146)
            CFrameMon = CFrame.new(-6037.66796875, 32.18463897705078, -1340.6597900390625)
        elseif MyLevel >= 1000 and MyLevel <= 1049 then
            Mon = "Snow Trooper"
            LevelQuest = 1
            NameQuest = "SnowMountainQuest"
            NameMon = "Snow Trooper"
            CFrameQuest = CFrame.new(609.858826, 400.119904, -5372.25928, -0.374604106, 0, 0.92718488, 0, 1, 0, -0.92718488, 0, -0.374604106)
            CFrameMon = CFrame.new(549.1473388671875, 427.3870544433594, -5563.69873046875)
        elseif MyLevel >= 1050 and MyLevel <= 1099 then
            Mon = "Winter Warrior"
            LevelQuest = 2
            NameQuest = "SnowMountainQuest"
            NameMon = "Winter Warrior"
            CFrameQuest = CFrame.new(609.858826, 400.119904, -5372.25928, -0.374604106, 0, 0.92718488, 0, 1, 0, -0.92718488, 0, -0.374604106)
            CFrameMon = CFrame.new(1142.7451171875, 475.6398010253906, -5199.41650390625)
        elseif MyLevel >= 1100 and MyLevel <= 1124 then
            Mon = "Lab Subordinate"
            LevelQuest = 1
            NameQuest = "IceSideQuest"
            NameMon = "Lab Subordinate"
            CFrameQuest = CFrame.new(-6064.06885, 15.2422857, -4902.97852, 0.453972578, -0, -0.891015649, 0, 1, -0, 0.891015649, 0, 0.453972578)
            CFrameMon = CFrame.new(-5707.4716796875, 15.951709747314453, -4513.39208984375)
        elseif MyLevel >= 1125 and MyLevel <= 1174 then
            Mon = "Horned Warrior"
            LevelQuest = 2
            NameQuest = "IceSideQuest"
            NameMon = "Horned Warrior"
            CFrameQuest = CFrame.new(-6064.06885, 15.2422857, -4902.97852, 0.453972578, -0, -0.891015649, 0, 1, -0, 0.891015649, 0, 0.453972578)
            CFrameMon = CFrame.new(-6341.36669921875, 15.951770782470703, -5723.162109375)
        elseif MyLevel >= 1175 and MyLevel <= 1199 then
            Mon = "Magma Ninja"
            LevelQuest = 1
            NameQuest = "FireSideQuest"
            NameMon = "Magma Ninja"
            CFrameQuest = CFrame.new(-5428.03174, 15.0622921, -5299.43457, -0.882952213, 0, 0.469463557, 0, 1, 0, -0.469463557, 0, -0.882952213)
            CFrameMon = CFrame.new(-5449.6728515625, 76.65874481201172, -5808.20068359375)
        elseif MyLevel >= 1200 and MyLevel <= 1249 then
            Mon = "Lava Pirate"
            LevelQuest = 2
            NameQuest = "FireSideQuest"
            NameMon = "Lava Pirate"
            CFrameQuest = CFrame.new(-5428.03174, 15.0622921, -5299.43457, -0.882952213, 0, 0.469463557, 0, 1, 0, -0.469463557, 0, -0.882952213)
            CFrameMon = CFrame.new(-5213.33154296875, 49.73788070678711, -4701.451171875)
        elseif MyLevel >= 1250 and MyLevel <= 1274 then
            Mon = "Ship Deckhand"
            LevelQuest = 1
            NameQuest = "ShipQuest1"
            NameMon = "Ship Deckhand"
            CFrameQuest = CFrame.new(1037.80127, 125.092171, 32911.6016)         
            CFrameMon = CFrame.new(1212.0111083984375, 150.79205322265625, 33059.24609375)    
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance",Vector3.new(923.21252441406, 126.9760055542, 32852.83203125))
            end
        elseif MyLevel >= 1275 and MyLevel <= 1299 then
            Mon = "Ship Engineer"
            LevelQuest = 2
            NameQuest = "ShipQuest1"
            NameMon = "Ship Engineer"
            CFrameQuest = CFrame.new(1037.80127, 125.092171, 32911.6016)   
            CFrameMon = CFrame.new(919.4786376953125, 43.54401397705078, 32779.96875)   
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance",Vector3.new(923.21252441406, 126.9760055542, 32852.83203125))
            end             
        elseif MyLevel >= 1300 and MyLevel <= 1324 then
            Mon = "Ship Steward"
            LevelQuest = 1
            NameQuest = "ShipQuest2"
            NameMon = "Ship Steward"
            CFrameQuest = CFrame.new(968.80957, 125.092171, 33244.125)         
            CFrameMon = CFrame.new(919.4385375976562, 129.55599975585938, 33436.03515625)      
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance",Vector3.new(923.21252441406, 126.9760055542, 32852.83203125))
            end
        elseif MyLevel >= 1325 and MyLevel <= 1349 then
            Mon = "Ship Officer"
            LevelQuest = 2
            NameQuest = "ShipQuest2"
            NameMon = "Ship Officer"
            CFrameQuest = CFrame.new(968.80957, 125.092171, 33244.125)
            CFrameMon = CFrame.new(1036.0179443359375, 181.4390411376953, 33315.7265625)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance",Vector3.new(923.21252441406, 126.9760055542, 32852.83203125))
            end
        elseif MyLevel >= 1350 and MyLevel <= 1374 then
            Mon = "Arctic Warrior"
            LevelQuest = 1
            NameQuest = "FrostQuest"
            NameMon = "Arctic Warrior"
            CFrameQuest = CFrame.new(5667.6582, 26.7997818, -6486.08984, -0.933587909, 0, -0.358349502, 0, 1, 0, 0.358349502, 0, -0.933587909)
            CFrameMon = CFrame.new(5966.24609375, 62.97002029418945, -6179.3828125)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance",Vector3.new(-6508.5581054688, 5000.034996032715, -132.83953857422))
            end
        elseif MyLevel >= 1375 and MyLevel <= 1424 then
            Mon = "Snow Lurker"
            LevelQuest = 2
            NameQuest = "FrostQuest"
            NameMon = "Snow Lurker"
            CFrameQuest = CFrame.new(5667.6582, 26.7997818, -6486.08984, -0.933587909, 0, -0.358349502, 0, 1, 0, 0.358349502, 0, -0.933587909)
            CFrameMon = CFrame.new(5407.07373046875, 69.19437408447266, -6880.88037109375)
        elseif MyLevel >= 1425 and MyLevel <= 1449 then
            Mon = "Sea Soldier"
            LevelQuest = 1
            NameQuest = "ForgottenQuest"
            NameMon = "Sea Soldier"
            CFrameQuest = CFrame.new(-3054.44458, 235.544281, -10142.8193, 0.990270376, -0, -0.13915664, 0, 1, -0, 0.13915664, 0, 0.990270376)
            CFrameMon = CFrame.new(-3028.2236328125, 64.67451477050781, -9775.4267578125)
        elseif MyLevel >= 1450 then
            Mon = "Water Fighter"
            LevelQuest = 2
            NameQuest = "ForgottenQuest"
            NameMon = "Water Fighter"
            CFrameQuest = CFrame.new(-3054, 240, -10146)
            CFrameMon = CFrame.new(-3291, 252, -10501)
        end
    elseif Sea3 then
        if MyLevel >= 1500 and MyLevel <= 1524 then
            Mon = "Pirate Millionaire"
            LevelQuest = 1
            NameQuest = "PiratePortQuest"
            NameMon = "Pirate Millionaire"
            CFrameQuest = CFrame.new(-290.074677, 42.9034653, 5581.58984, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627)
            CFrameMon = CFrame.new(-245.9963836669922, 47.30615234375, 5584.1005859375)
        elseif MyLevel >= 1525 and MyLevel <= 1574 then
            Mon = "Pistol Billionaire"
            LevelQuest = 2
            NameQuest = "PiratePortQuest"
            NameMon = "Pistol Billionaire"
            CFrameQuest = CFrame.new(-290.074677, 42.9034653, 5581.58984, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627)
            CFrameMon = CFrame.new(-187.3301544189453, 86.23987579345703, 6013.513671875)
        elseif MyLevel >= 1575 and MyLevel <= 1599 then
            Mon = "Dragon Crew Warrior"
            LevelQuest = 1
            NameQuest = "DragonCrewQuest"
            NameMon = "Dragon Crew Warrior"
            CFrameQuest = CFrame.new(6738.96142578125, 127.81645965576172, -713.511474609375)
            CFrameMon = CFrame.new(6920.71435546875, 56.15597152709961, -942.5044555664062)
        elseif MyLevel >= 1600 and MyLevel <= 1624 then 
            Mon = "Dragon Crew Archer"
            NameQuest = "DragonCrewQuest"
            LevelQuest = 2
            NameMon = "Dragon Crew Archer"
            CFrameQuest = CFrame.new(6738.96142578125, 127.81645965576172, -713.511474609375)
            CFrameMon = CFrame.new(6817.91259765625, 484.804443359375, 513.4141235351562)
        elseif MyLevel >= 1625 and MyLevel <= 1649 then
            Mon = "Hydra Enforcer"
            NameQuest = "VenomCrewQuest"
            LevelQuest = 1
            NameMon = "Hydra Enforcer"
            CFrameQuest = CFrame.new(5213.8740234375, 1004.5042724609375, 758.6944580078125)
            CFrameMon = CFrame.new(4584.69287109375, 1002.6435546875, 705.7958984375)
        elseif MyLevel >= 1650 and MyLevel <= 1699 then 
            Mon = "Venomous Assailant"
            NameQuest = "VenomCrewQuest"
            LevelQuest = 2
            NameMon = "Venomous Assailant"
            CFrameQuest = CFrame.new(5213.8740234375, 1004.5042724609375, 758.6944580078125)
            CFrameMon = CFrame.new(4638.78564453125, 1078.94091796875, 881.8002319335938)        
        elseif MyLevel >= 1700 and MyLevel <= 1724 then
            Mon = "Marine Commodore"
            LevelQuest = 1
            NameQuest = "MarineTreeIsland"
            NameMon = "Marine Commodore"
            CFrameQuest = CFrame.new(2180.54126, 27.8156815, -6741.5498, -0.965929747, 0, 0.258804798, 0, 1, 0, -0.258804798, 0, -0.965929747)
            CFrameMon = CFrame.new(2286.0078125, 73.13391876220703, -7159.80908203125)
        elseif MyLevel >= 1725 and MyLevel <= 1774 then
            Mon = "Marine Rear Admiral"
            NameMon = "Marine Rear Admiral"
            NameQuest = "MarineTreeIsland"
            LevelQuest = 2
            CFrameQuest = CFrame.new(2179.98828125, 28.731239318848, -6740.0551757813)
            CFrameMon = CFrame.new(3656.773681640625, 160.52406311035156, -7001.5986328125)
        elseif MyLevel >= 1775 and MyLevel <= 1799 then
            Mon = "Fishman Raider"
            LevelQuest = 1
            NameQuest = "DeepForestIsland3"
            NameMon = "Fishman Raider"
            CFrameQuest = CFrame.new(-10581.6563, 330.872955, -8761.18652, -0.882952213, 0, 0.469463557, 0, 1, 0, -0.469463557, 0, -0.882952213)   
            CFrameMon = CFrame.new(-10407.5263671875, 331.76263427734375, -8368.5166015625)
        elseif MyLevel >= 1800 and MyLevel <= 1824 then
            Mon = "Fishman Captain"
            LevelQuest = 2
            NameQuest = "DeepForestIsland3"
            NameMon = "Fishman Captain"
            CFrameQuest = CFrame.new(-10581.6563, 330.872955, -8761.18652, -0.882952213, 0, 0.469463557, 0, 1, 0, -0.469463557, 0, -0.882952213)   
            CFrameMon = CFrame.new(-10994.701171875, 352.38140869140625, -9002.1103515625) 
        elseif MyLevel >= 1825 and MyLevel <= 1849 then
            Mon = "Forest Pirate"
            LevelQuest = 1
            NameQuest = "DeepForestIsland"
            NameMon = "Forest Pirate"
            CFrameQuest = CFrame.new(-13234.04, 331.488495, -7625.40137, 0.707134247, -0, -0.707079291, 0, 1, -0, 0.707079291, 0, 0.707134247)
            CFrameMon = CFrame.new(-13274.478515625, 332.3781433105469, -7769.58056640625)
        elseif MyLevel >= 1850 and MyLevel <= 1899 then
            Mon = "Mythological Pirate"
            LevelQuest = 2
            NameQuest = "DeepForestIsland"
            NameMon = "Mythological Pirate"
            CFrameQuest = CFrame.new(-13234.04, 331.488495, -7625.40137, 0.707134247, -0, -0.707079291, 0, 1, -0, 0.707079291, 0, 0.707134247)   
            CFrameMon = CFrame.new(-13680.607421875, 501.08154296875, -6991.189453125)
        elseif MyLevel >= 1900 and MyLevel <= 1924 then
            Mon = "Jungle Pirate"
            LevelQuest = 1
            NameQuest = "DeepForestIsland2"
            NameMon = "Jungle Pirate"
            CFrameQuest = CFrame.new(-12680.3818, 389.971039, -9902.01953, -0.0871315002, 0, 0.996196866, 0, 1, 0, -0.996196866, 0, -0.0871315002)
            CFrameMon = CFrame.new(-12256.16015625, 331.73828125, -10485.8369140625)
        elseif MyLevel >= 1925 and MyLevel <= 1974 then
            Mon = "Musketeer Pirate"
            LevelQuest = 2
            NameQuest = "DeepForestIsland2"
            NameMon = "Musketeer Pirate"
            CFrameQuest = CFrame.new(-12680.3818, 389.971039, -9902.01953, -0.0871315002, 0, 0.996196866, 0, 1, 0, -0.996196866, 0, -0.0871315002)
            CFrameMon = CFrame.new(-13457.904296875, 391.545654296875, -9859.177734375)
        elseif MyLevel >= 1975 and MyLevel <= 1999 then
            Mon = "Reborn Skeleton"
            LevelQuest = 1
            NameQuest = "HauntedQuest1"
            NameMon = "Reborn Skeleton"
            CFrameQuest = CFrame.new(-9479.2168, 141.215088, 5566.09277, 0, 0, 1, 0, 1, -0, -1, 0, 0)
            CFrameMon = CFrame.new(-8763.7236328125, 165.72299194335938, 6159.86181640625)
        elseif MyLevel >= 2000 and MyLevel <= 2024 then
            Mon = "Living Zombie"
            LevelQuest = 2
            NameQuest = "HauntedQuest1"
            NameMon = "Living Zombie"
            CFrameQuest = CFrame.new(-9479.2168, 141.215088, 5566.09277, 0, 0, 1, 0, 1, -0, -1, 0, 0)
            CFrameMon = CFrame.new(-10144.1318359375, 138.62667846679688, 5838.0888671875)
        elseif MyLevel >= 2025 and MyLevel <= 2049 then
            Mon = "Demonic Soul"
            LevelQuest = 1
            NameQuest = "HauntedQuest2"
            NameMon = "Demonic Soul"
            CFrameQuest = CFrame.new(-9516.99316, 172.017181, 6078.46533, 0, 0, -1, 0, 1, 0, 1, 0, 0) 
            CFrameMon = CFrame.new(-9505.8720703125, 172.10482788085938, 6158.9931640625)
        elseif MyLevel >= 2050 and MyLevel <= 2074 then
            Mon = "Posessed Mummy"
            LevelQuest = 2
            NameQuest = "HauntedQuest2"
            NameMon = "Posessed Mummy"
            CFrameQuest = CFrame.new(-9516.99316, 172.017181, 6078.46533, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            CFrameMon = CFrame.new(-9582.0224609375, 6.251527309417725, 6205.478515625)
        elseif MyLevel >= 2075 and MyLevel <= 2099 then
            Mon = "Peanut Scout"
            LevelQuest = 1
            NameQuest = "NutsIslandQuest"
            NameMon = "Peanut Scout"
            CFrameQuest = CFrame.new(-2104.3908691406, 38.104167938232, -10194.21875, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            CFrameMon = CFrame.new(-2143.241943359375, 47.72198486328125, -10029.9951171875)
        elseif MyLevel >= 2100 and MyLevel <= 2124 then
            Mon = "Peanut President"
            LevelQuest = 2
            NameQuest = "NutsIslandQuest"
            NameMon = "Peanut President"
            CFrameQuest = CFrame.new(-2104.3908691406, 38.104167938232, -10194.21875, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            CFrameMon = CFrame.new(-1859.35400390625, 38.10316848754883, -10422.4296875)
        elseif MyLevel >= 2125 and MyLevel <= 2149 then
            Mon = "Ice Cream Chef"
            LevelQuest = 1
            NameQuest = "IceCreamIslandQuest"
            NameMon = "Ice Cream Chef"
            CFrameQuest = CFrame.new(-820.64825439453, 65.819526672363, -10965.795898438, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            CFrameMon = CFrame.new(-872.24658203125, 65.81957244873047, -10919.95703125)
        elseif MyLevel >= 2150 and MyLevel <= 2199 then
            Mon = "Ice Cream Commander"
            LevelQuest = 2
            NameQuest = "IceCreamIslandQuest"
            NameMon = "Ice Cream Commander"
            CFrameQuest = CFrame.new(-820.64825439453, 65.819526672363, -10965.795898438, 0, 0, -1, 0, 1, 0, 1, 0, 0)
            CFrameMon = CFrame.new(-558.06103515625, 112.04895782470703, -11290.7744140625)
        elseif MyLevel >= 2200 and MyLevel <= 2224 then
            Mon = "Cookie Crafter"
            LevelQuest = 1
            NameQuest = "CakeQuest1"
            NameMon = "Cookie Crafter"
            CFrameQuest = CFrame.new(-2021.32007, 37.7982254, -12028.7295, 0.957576931, -8.80302053e-08, 0.288177818, 6.9301187e-08, 1, 7.51931211e-08, -0.288177818, -5.2032135e-08, 0.957576931)
            CFrameMon = CFrame.new(-2374.13671875, 37.79826354980469, -12125.30859375)
        elseif MyLevel >= 2225 and MyLevel <= 2249 then
            Mon = "Cake Guard"
            LevelQuest = 2
            NameQuest = "CakeQuest1"
            NameMon = "Cake Guard"
            CFrameQuest = CFrame.new(-2021.32007, 37.7982254, -12028.7295, 0.957576931, -8.80302053e-08, 0.288177818, 6.9301187e-08, 1, 7.51931211e-08, -0.288177818, -5.2032135e-08, 0.957576931)
            CFrameMon = CFrame.new(-1598.3070068359375, 43.773197174072266, -12244.5810546875)
        elseif MyLevel >= 2250 and MyLevel <= 2274 then
            Mon = "Baking Staff"
            LevelQuest = 1
            NameQuest = "CakeQuest2"
            NameMon = "Baking Staff"
            CFrameQuest = CFrame.new(-1927.91602, 37.7981339, -12842.5391, -0.96804446, 4.22142143e-08, 0.250778586, 4.74911062e-08, 1, 1.49904711e-08, -0.250778586, 2.64211941e-08, -0.96804446)
            CFrameMon = CFrame.new(-1887.8099365234375, 77.6185073852539, -12998.3505859375)
        elseif MyLevel >= 2275 and MyLevel <= 2299 then
            Mon = "Head Baker"
            LevelQuest = 2
            NameQuest = "CakeQuest2"
            NameMon = "Head Baker"
            CFrameQuest = CFrame.new(-1927.91602, 37.7981339, -12842.5391, -0.96804446, 4.22142143e-08, 0.250778586, 4.74911062e-08, 1, 1.49904711e-08, -0.250778586, 2.64211941e-08, -0.96804446)
            CFrameMon = CFrame.new(-2216.188232421875, 82.884521484375, -12869.2939453125)
        elseif MyLevel >= 2300 and MyLevel <= 2324 then
            Mon = "Cocoa Warrior"
            LevelQuest = 1
            NameQuest = "ChocQuest1"
            NameMon = "Cocoa Warrior"
            CFrameQuest = CFrame.new(233.22836303710938, 29.876001358032227, -12201.2333984375)
            CFrameMon = CFrame.new(-21.55328369140625, 80.57499694824219, -12352.3876953125)
        elseif MyLevel >= 2325 and MyLevel <= 2349 then
            Mon = "Chocolate Bar Battler"
            LevelQuest = 2
            NameQuest = "ChocQuest1"
            NameMon = "Chocolate Bar Battler"
            CFrameQuest = CFrame.new(233.22836303710938, 29.876001358032227, -12201.2333984375)
            CFrameMon = CFrame.new(582.590576171875, 77.18809509277344, -12463.162109375)
        elseif MyLevel >= 2350 and MyLevel <= 2374 then
            Mon = "Sweet Thief"
            LevelQuest = 1
            NameQuest = "ChocQuest2"
            NameMon = "Sweet Thief"
            CFrameQuest = CFrame.new(150.5066375732422, 30.693693161010742, -12774.5029296875)
            CFrameMon = CFrame.new(165.1884765625, 76.05885314941406, -12600.8369140625)
        elseif MyLevel >= 2375 and MyLevel <= 2399 then
            Mon = "Candy Rebel"
            LevelQuest = 2
            NameQuest = "ChocQuest2"
            NameMon = "Candy Rebel"
            CFrameQuest = CFrame.new(150.5066375732422, 30.693693161010742, -12774.5029296875)
            CFrameMon = CFrame.new(134.86563110351562, 77.2476806640625, -12876.5478515625)
        elseif MyLevel >= 2400 and MyLevel <= 2424 then
            Mon = "Candy Pirate"
            LevelQuest = 1
            NameQuest = "CandyQuest1"
            NameMon = "Candy Pirate"
            CFrameQuest = CFrame.new(-1150.0400390625, 20.378934860229492, -14446.3349609375)
            CFrameMon = CFrame.new(-1310.5003662109375, 26.016523361206055, -14562.404296875)
        elseif MyLevel >= 2425 and MyLevel <= 2449 then
            Mon = "Snow Demon"
            LevelQuest = 2
            NameQuest = "CandyQuest1"
            NameMon = "Snow Demon"
            CFrameQuest = CFrame.new(-1150.0400390625, 20.378934860229492, -14446.3349609375)
            CFrameMon = CFrame.new(-880.2006225585938, 71.24776458740234, -14538.609375)            
        elseif MyLevel >= 2450 and MyLevel <= 2474 then
            Mon = "Isle Outlaw"
            LevelQuest = 1
            NameQuest = "TikiQuest1"
            NameMon = "Isle Outlaw"
            CFrameQuest = CFrame.new(-16547.748046875, 61.13533401489258, -173.41360473632812)
            CFrameMon = CFrame.new(-16442.814453125, 116.13899993896484, -264.4637756347656)
        elseif MyLevel >= 2475 and MyLevel <= 2524 then
            Mon = "Island Boy"
            LevelQuest = 2
            NameQuest = "TikiQuest1"
            NameMon = "Island Boy"
            CFrameQuest = CFrame.new(-16547.748046875, 61.13533401489258, -173.41360473632812)
            CFrameMon = CFrame.new(-16901.26171875, 84.06756591796875, -192.88906860351562)
        elseif MyLevel >= 2525 and MyLevel <= 2550 then
            Mon = "Isle Champion"
            LevelQuest = 2
            NameQuest = "TikiQuest2"
            NameMon = "Isle Champion"
            CFrameQuest = CFrame.new(-16539.078125, 55.68632888793945, 1051.5738525390625)
            CFrameMon = CFrame.new(-16641.6796875, 235.7825469970703, 1031.282958984375)
        elseif MyLevel >= 2550 and MyLevel <= 2574 then
            Mon = "Serpent Hunter"
            LevelQuest = 1
            NameQuest = "TikiQuest3"
            NameMon = "Serpent Hunter"
            CFrameQuest = CFrame.new(-16665.1914, 104.596405, 1579.69434, 0.951068401, -0, -0.308980465, 0, 1, -0, 0.308980465, 0, 0.951068401)
            CFrameMon = CFrame.new(-16521.0625, 106.09285, 1488.78467, 0.469467044, 0, 0.882950008, 0, 1, 0, -0.882950008, 0, 0.469467044)
        elseif MyLevel >= 2575 and MyLevel <= 2599 then
            Mon = "Skull Slayer"
            LevelQuest = 2
            NameQuest = "TikiQuest3"
            NameMon = "Skull Slayer"
            CFrameQuest = CFrame.new(-16665.1914, 104.596405, 1579.69434, 0.951068401, -0, -0.308980465, 0, 1, -0, 0.308980465, 0, 0.951068401)
            CFrameMon = CFrame.new(-16887.7305, 113.074638, 1629.97778, -0.559032857, 1.2313353e-08, -0.829145491, 1.05618814e-09, 1, 1.41385428e-08, 0.829145491, 7.02817626e-09, -0.559032857)           
        elseif MyLevel >= 2600 and MyLevel <= 2624 then
            Mon = "Reef Bandit"
            LevelQuest = 1
            NameQuest = "SubmergedQuest1"
            NameMon = "Reef Bandits"
            CFrameQuest = CFrame.new(10778.875, -2087.72437, 9265.18359, 0.934615612, -9.33109447e-08, -0.355659455, 9.17655143e-08, 1, -2.12154276e-08, 0.355659455, -1.28090019e-08, 0.934615612)
            CFrameMon = CFrame.new(11019.1318, -2146.06812, 9342.3916, -0.719955266, -1.74275385e-08, 0.69402045, 5.76556367e-08, 1, 8.49211546e-08, -0.69402045, 1.01153624e-07, -0.719955266)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                local args = {"TravelToSubmergedIsland"} game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/SubmarineWorkerSpeak"):InvokeServer(unpack(args))
            end             
        elseif MyLevel >= 2625 and MyLevel <= 2649 then
            Mon = "Coral Pirate"
            LevelQuest = 2
            NameQuest = "SubmergedQuest1"
            NameMon = "Coral Pirates"
            CFrameQuest = CFrame.new(10778.875, -2087.72437, 9265.18359, 0.934615612, -9.33109447e-08, -0.355659455, 9.17655143e-08, 1, -2.12154276e-08, 0.355659455, -1.28090019e-08, 0.934615612)
            CFrameMon = CFrame.new(10808.6006, -2030.36145, 9364.2334, -0.775185347, -0.0359364748, 0.6307109, 0.0615428537, 0.989336014, 0.132010356, -0.628728986, 0.141148239, -0.764707148)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                local args = {"TravelToSubmergedIsland"} game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/SubmarineWorkerSpeak"):InvokeServer(unpack(args))
            end
        elseif MyLevel >= 2650 and MyLevel <= 2674 then
            Mon = "Sea Chanter"
            LevelQuest = 1
            NameQuest = "SubmergedQuest2"
            NameMon = "Sea Chanters"
            CFrameQuest = CFrame.new(10880.6855, -2086.20044, 10032.624, -0.321384728, 9.87648434e-08, -0.946948707, 7.13271007e-08, 1, 8.00902953e-08, 0.946948707, -4.18033075e-08, -0.321384728)
            CFrameMon = CFrame.new(10671.2715, -2057.59155, 10047.2588, -0.846484065, -3.11045447e-08, 0.532414079, -5.55383117e-08, 1, -2.98785316e-08, -0.532414079, -5.48610757e-08, -0.846484065)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                local args = {"TravelToSubmergedIsland"} game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/SubmarineWorkerSpeak"):InvokeServer(unpack(args))
            end
        elseif MyLevel >= 2675 and MyLevel <= 2750 then             
            Mon = "Ocean Prophet"
            LevelQuest = 2
            NameQuest = "SubmergedQuest2"
            NameMon = "Ocean Prophets"
            CFrameQuest = CFrame.new(10880.6855, -2086.20044, 10032.624, -0.321384728, 9.87648434e-08, -0.946948707, 7.13271007e-08, 1, 8.00902953e-08, 0.946948707, -4.18033075e-08, -0.321384728)
            CFrameMon = CFrame.new(11008.5195, -2007.72839, 10223.0791, -0.688615739, 2.33523378e-09, -0.725126445, 2.99292546e-09, 1, 3.78221315e-10, 0.725126445, -1.90980032e-09, -0.688615739)
            if _G.AutoLevel and (CFrameQuest.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 10000 then
                local args = {"TravelToSubmergedIsland"} game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/SubmarineWorkerSpeak"):InvokeServer(unpack(args))
            end               
        end
    end
end        
if Sea1 then
	tableMon = {"Bandit","Monkey","Gorilla","Pirate","Brute","Desert Bandit","Desert Officer","Snow Bandit","Snowman","Chief Petty Officer","Sky Bandit","Dark Master","Prisoner","Dangerous Prisoner","Toga Warrior","Gladiator","Military Soldier","Military Spy","Fishman Warrior","Fishman Commando","God's Guard","Shanda","Royal Squad","Royal Soldier","Galley Pirate","Galley Captain"};
elseif Sea2 then
	tableMon = {"Raider","Mercenary","Swan Pirate","Factory Staff","Marine Lieutenant","Marine Captain","Zombie","Vampire","Snow Trooper","Winter Warrior","Lab Subordinate","Horned Warrior","Magma Ninja","Lava Pirate","Ship Deckhand","Ship Engineer","Ship Steward","Ship Officer","Arctic Warrior","Snow Lurker","Sea Soldier","Water Fighter"};
elseif Sea3 then
	tableMon = {"Pirate Millionaire","Dragon Crew Warrior","Dragon Crew Archer","Hydra Enforcer","Venomous Assailant","Marine Commodore","Marine Rear Admiral","Fishman Raider","Fishman Captain","Forest Pirate","Mythological Pirate","Jungle Pirate","Musketeer Pirate","Reborn Skeleton","Living Zombie","Demonic Soul","Posessed Mummy","Peanut Scout","Peanut President","Ice Cream Chef","Ice Cream Commander","Cookie Crafter","Cake Guard","Baking Staff","Head Baker","Cocoa Warrior","Chocolate Bar Battler","Sweet Thief","Candy Rebel","Candy Pirate","Snow Demon","Isle Outlaw","Island Boy","Sun-kissed Warrior","Isle Champion","Serpent Hunter","Skull Slayer"};
end
if Sea1 then
	AreaList = {"Jungle","Buggy","Desert","Snow","Marine","Sky","Prison","Colosseum","Magma","Fishman","Sky Island","Fountain"};
elseif Sea2 then
	AreaList = {"Area 1","Area 2","Zombie","Marine","Snow Mountain","Ice fire","Ship","Frost","Forgotten"};
elseif Sea3 then
	AreaList = {"Pirate Port","Amazon","Marine Tree","Deep Forest","Haunted Castle","Nut Island","Ice Cream Island","Cake Island","Choco Island","Candy Island","Tiki Outpost"};
end
function CheckBossQuest()
	if Sea1 then
		if (SelectBoss == "The Gorilla King") then
			BossMon = "The Gorilla King";
			NameBoss = "The Gorrila King";
			NameQuestBoss = "JungleQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$2,000\n7,000 Exp.";
			CFrameQBoss = CFrame.new(-1601.6553955078, 36.85213470459, 153.38809204102);
			CFrameBoss = CFrame.new(-1088.75977, 8.13463783, -488.559906, -0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, -0.707134247);
		elseif (SelectBoss == "Bobby") then
			BossMon = "Bobby";
			NameBoss = "Bobby";
			NameQuestBoss = "BuggyQuest1";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$8,000\n35,000 Exp.";
			CFrameQBoss = CFrame.new(-1140.1761474609, 4.752049446106, 3827.4057617188);
			CFrameBoss = CFrame.new(-1087.3760986328, 46.949409484863, 4040.1462402344);
		elseif (SelectBoss == "The Saw") then
			BossMon = "The Saw";
			NameBoss = "The Saw";
			CFrameBoss = CFrame.new(-784.89715576172, 72.427383422852, 1603.5822753906);
		elseif (SelectBoss == "Yeti") then
			BossMon = "Yeti";
			NameBoss = "Yeti";
			NameQuestBoss = "SnowQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$10,000\n180,000 Exp.";
			CFrameQBoss = CFrame.new(1386.8073730469, 87.272789001465, -1298.3576660156);
			CFrameBoss = CFrame.new(1218.7956542969, 138.01184082031, -1488.0262451172);
		elseif (SelectBoss == "Mob Leader") then
			BossMon = "Mob Leader";
			NameBoss = "Mob Leader";
			CFrameBoss = CFrame.new(-2844.7307128906, 7.4180502891541, 5356.6723632813);
		elseif (SelectBoss == "Vice Admiral") then
			BossMon = "Vice Admiral";
			NameBoss = "Vice Admiral";
			NameQuestBoss = "MarineQuest2";
			QuestLvBoss = 2;
			RewardBoss = "Reward:\n$10,000\n180,000 Exp.";
			CFrameQBoss = CFrame.new(-5036.2465820313, 28.677835464478, 4324.56640625);
			CFrameBoss = CFrame.new(-5006.5454101563, 88.032081604004, 4353.162109375);
		elseif (SelectBoss == "Saber Expert") then
			NameBoss = "Saber Expert";
			BossMon = "Saber Expert";
			CFrameBoss = CFrame.new(-1458.89502, 29.8870335, -50.633564);
		elseif (SelectBoss == "Warden") then
			BossMon = "Warden";
			NameBoss = "Warden";
			NameQuestBoss = "ImpelQuest";
			QuestLvBoss = 1;
			RewardBoss = "Reward:\n$6,000\n850,000 Exp.";
			CFrameBoss = CFrame.new(5278.04932, 2.15167475, 944.101929, 0.220546961, -0.000004499464, 0.975376427, -0.000019541258, 1, 0.000009031621, -0.975376427, -0.000021051976, 0.220546961);
			CFrameQBoss = CFrame.new(5191.86133, 2.84020686, 686.438721, -0.731384635, 0, 0.681965172, 0, 1, 0, -0.681965172, 0, -0.731384635);
		elseif (SelectBoss == "Chief Warden") then
			BossMon = "Chief Warden";
			NameBoss = "Chief Warden";
			NameQuestBoss = "ImpelQuest";
			QuestLvBoss = 2;
			RewardBoss = "Reward:\n$10,000\n1,000,000 Exp.";
			CFrameBoss = CFrame.new(5206.92578, 0.997753382, 814.976746, 0.342041343, -0.00062915677, 0.939684749, 0.00191645394, 0.999998152, -0.000028042234, -0.939682961, 0.00181045406, 0.342041939);
			CFrameQBoss = CFrame.new(5191.86133, 2.84020686, 686.438721, -0.731384635, 0, 0.681965172, 0, 1, 0, -0.681965172, 0, -0.731384635);
		elseif (SelectBoss == "Swan") then
			BossMon = "Swan";
			NameBoss = "Swan";
			NameQuestBoss = "ImpelQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$15,000\n1,600,000 Exp.";
			CFrameBoss = CFrame.new(5325.09619, 7.03906584, 719.570679, -0.309060812, 0, 0.951042235, 0, 1, 0, -0.951042235, 0, -0.309060812);
			CFrameQBoss = CFrame.new(5191.86133, 2.84020686, 686.438721, -0.731384635, 0, 0.681965172, 0, 1, 0, -0.681965172, 0, -0.731384635);
		elseif (SelectBoss == "Magma Admiral") then
			BossMon = "Magma Admiral";
			NameBoss = "Magma Admiral";
			NameQuestBoss = "MagmaQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$15,000\n2,800,000 Exp.";
			CFrameQBoss = CFrame.new(-5314.6220703125, 12.262420654297, 8517.279296875);
			CFrameBoss = CFrame.new(-5765.8969726563, 82.92064666748, 8718.3046875);
		elseif (SelectBoss == "Fishman Lord") then
			BossMon = "Fishman Lord";
			NameBoss = "Fishman Lord";
			NameQuestBoss = "FishmanQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$15,000\n4,000,000 Exp.";
			CFrameQBoss = CFrame.new(61122.65234375, 18.497442245483, 1569.3997802734);
			CFrameBoss = CFrame.new(61260.15234375, 30.950881958008, 1193.4329833984);
		elseif (SelectBoss == "Wysper") then
			BossMon = "Wysper";
			NameBoss = "Wysper";
			NameQuestBoss = "SkyExp1Quest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$15,000\n4,800,000 Exp.";
			CFrameQBoss = CFrame.new(-7861.947265625, 5545.517578125, -379.85974121094);
			CFrameBoss = CFrame.new(-7866.1333007813, 5576.4311523438, -546.74816894531);
		elseif (SelectBoss == "Thunder God") then
			BossMon = "Thunder God";
			NameBoss = "Thunder God";
			NameQuestBoss = "SkyExp2Quest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$20,000\n5,800,000 Exp.";
			CFrameQBoss = CFrame.new(-7903.3828125, 5635.9897460938, -1410.923828125);
			CFrameBoss = CFrame.new(-7994.984375, 5761.025390625, -2088.6479492188);
		elseif (SelectBoss == "Cyborg") then
			BossMon = "Cyborg";
			NameBoss = "Cyborg";
			NameQuestBoss = "FountainQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$20,000\n7,500,000 Exp.";
			CFrameQBoss = CFrame.new(5258.2788085938, 38.526931762695, 4050.044921875);
			CFrameBoss = CFrame.new(6094.0249023438, 73.770050048828, 3825.7348632813);
		elseif (SelectBoss == "Ice Admiral") then
			BossMon = "Ice Admiral";
			NameBoss = "Ice Admiral";
			CFrameBoss = CFrame.new(1266.08948, 26.1757946, -1399.57678, -0.573599219, 0, -0.81913656, 0, 1, 0, 0.81913656, 0, -0.573599219);
		elseif (SelectBoss == "Greybeard") then
			BossMon = "Greybeard";
			NameBoss = "Greybeard";
			CFrameBoss = CFrame.new(-5081.3452148438, 85.221641540527, 4257.3588867188);
		end
	end
	if Sea2 then
		if (SelectBoss == "Diamond") then
			BossMon = "Diamond";
			NameBoss = "Diamond";
			NameQuestBoss = "Area1Quest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$25,000\n9,000,000 Exp.";
			CFrameQBoss = CFrame.new(-427.5666809082, 73.313781738281, 1835.4208984375);
			CFrameBoss = CFrame.new(-1576.7166748047, 198.59265136719, 13.724286079407);
		elseif (SelectBoss == "Jeremy") then
			BossMon = "Jeremy";
			NameBoss = "Jeremy";
			NameQuestBoss = "Area2Quest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$25,000\n11,500,000 Exp.";
			CFrameQBoss = CFrame.new(636.79943847656, 73.413787841797, 918.00415039063);
			CFrameBoss = CFrame.new(2006.9261474609, 448.95666503906, 853.98284912109);
		elseif (SelectBoss == "Fajita") then
			BossMon = "Fajita";
			NameBoss = "Fajita";
			NameQuestBoss = "MarineQuest3";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$25,000\n15,000,000 Exp.";
			CFrameQBoss = CFrame.new(-2441.986328125, 73.359344482422, -3217.5324707031);
			CFrameBoss = CFrame.new(-2172.7399902344, 103.32216644287, -4015.025390625);
		elseif (SelectBoss == "Don Swan") then
			BossMon = "Don Swan";
			NameBoss = "Don Swan";
			CFrameBoss = CFrame.new(2286.2004394531, 15.177839279175, 863.8388671875);
		elseif (SelectBoss == "Smoke Admiral") then
			BossMon = "Smoke Admiral";
			NameBoss = "Smoke Admiral";
			NameQuestBoss = "IceSideQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$20,000\n25,000,000 Exp.";
			CFrameQBoss = CFrame.new(-5429.0473632813, 15.977565765381, -5297.9614257813);
			CFrameBoss = CFrame.new(-5275.1987304688, 20.757257461548, -5260.6669921875);
		elseif (SelectBoss == "Awakened Ice Admiral") then
			BossMon = "Awakened Ice Admiral";
			NameBoss = "Awakened Ice Admiral";
			NameQuestBoss = "FrostQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$20,000\n36,000,000 Exp.";
			CFrameQBoss = CFrame.new(5668.9780273438, 28.519989013672, -6483.3520507813);
			CFrameBoss = CFrame.new(6403.5439453125, 340.29766845703, -6894.5595703125);
		elseif (SelectBoss == "Tide Keeper") then
			BossMon = "Tide Keeper";
			NameBoss = "Tide Keeper";
			NameQuestBoss = "ForgottenQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$12,500\n38,000,000 Exp.";
			CFrameQBoss = CFrame.new(-3053.9814453125, 237.18954467773, -10145.0390625);
			CFrameBoss = CFrame.new(-3795.6423339844, 105.88877105713, -11421.307617188);
		elseif (SelectBoss == "Darkbeard") then
			BossMon = "Darkbeard";
			NameBoss = "Darkbeard";
			CFrameMon = CFrame.new(3677.08203125, 62.751937866211, -3144.8332519531);
		elseif (SelectBoss == "Cursed Captain") then
			BossMon = "Cursed Captain";
			NameBoss = "Cursed Captain";
			CFrameBoss = CFrame.new(916.928589, 181.092773, 33422);
		elseif (SelectBoss == "Order") then
			BossMon = "Order";
			NameBoss = "Order";
			CFrameBoss = CFrame.new(-6217.2021484375, 28.047645568848, -5053.1357421875);
		end
	end
	if Sea3 then
		if (SelectBoss == "Stone") then
			BossMon = "Stone";
			NameBoss = "Stone";
			NameQuestBoss = "PiratePortQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$25,000\n40,000,000 Exp.";
			CFrameQBoss = CFrame.new(-289.76705932617, 43.819011688232, 5579.9384765625);
			CFrameBoss = CFrame.new(-1027.6512451172, 92.404174804688, 6578.8530273438);
		elseif (SelectBoss == "Hydra Leader") then
			BossMon = "Hydra Leader";
			NameBoss = "Hydra Leader";
			NameQuestBoss = "VenomCrewQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$30,000\n52,000,000 Exp.";
			CFrameQBoss = CFrame.new(5445.9541015625, 601.62945556641, 751.43792724609);
			CFrameBoss = CFrame.new(5543.86328125, 668.97399902344, 199.0341796875);
		elseif (SelectBoss == "Kilo Admiral") then
			BossMon = "Kilo Admiral";
			NameBoss = "Kilo Admiral";
			NameQuestBoss = "MarineTreeIsland";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$35,000\n56,000,000 Exp.";
			CFrameQBoss = CFrame.new(2179.3010253906, 28.731239318848, -6739.9741210938);
			CFrameBoss = CFrame.new(2764.2233886719, 432.46154785156, -7144.4580078125);
		elseif (SelectBoss == "Captain Elephant") then
			BossMon = "Captain Elephant";
			NameBoss = "Captain Elephant";
			NameQuestBoss = "DeepForestIsland";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$40,000\n67,000,000 Exp.";
			CFrameQBoss = CFrame.new(-13232.682617188, 332.40396118164, -7626.01171875);
			CFrameBoss = CFrame.new(-13376.7578125, 433.28689575195, -8071.392578125);
		elseif (SelectBoss == "Beautiful Pirate") then
			BossMon = "Beautiful Pirate";
			NameBoss = "Beautiful Pirate";
			NameQuestBoss = "DeepForestIsland2";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$50,000\n70,000,000 Exp.";
			CFrameQBoss = CFrame.new(-12682.096679688, 390.88653564453, -9902.1240234375);
			CFrameBoss = CFrame.new(5283.609375, 22.56223487854, -110.78285217285);
		elseif (SelectBoss == "Cake Queen") then
			BossMon = "Cake Queen";
			NameBoss = "Cake Queen";
			NameQuestBoss = "IceCreamIslandQuest";
			QuestLvBoss = 3;
			RewardBoss = "Reward:\n$30,000\n112,500,000 Exp.";
			CFrameQBoss = CFrame.new(-819.376709, 64.9259796, -10967.2832, -0.766061664, 0, 0.642767608, 0, 1, 0, -0.642767608, 0, -0.766061664);
			CFrameBoss = CFrame.new(-678.648804, 381.353943, -11114.2012, -0.908641815, 0.00149294338, 0.41757378, 0.00837114919, 0.999857843, 0.0146408929, -0.417492568, 0.0167988986, -0.90852499);
		elseif (SelectBoss == "Longma") then
			BossMon = "Longma";
			NameBoss = "Longma";
			CFrameBoss = CFrame.new(-10238.875976563, 389.7912902832, -9549.7939453125);
		elseif (SelectBoss == "Soul Reaper") then
			BossMon = "Soul Reaper";
			NameBoss = "Soul Reaper";
			CFrameBoss = CFrame.new(-9524.7890625, 315.80429077148, 6655.7192382813);
		elseif (SelectBoss == "rip_indra True Form") then
			BossMon = "rip_indra True Form";
			NameBoss = "rip_indra True Form";
			CFrameBoss = CFrame.new(-5415.3920898438, 505.74133300781, -2814.0166015625);
		end
	end
end
function MaterialMon()
	if (SelectMaterial == "Radioactive Material") then
		MMon = "Factory Staff";
		MPos = CFrame.new(295, 73, -56);
		SP = "Default";
	elseif (SelectMaterial == "Mystic Droplet") then
		MMon = "Water Fighter";
		MPos = CFrame.new(-3385, 239, -10542);
		SP = "Default";
	elseif (SelectMaterial == "Magma Ore") then
		if Sea1 then
			MMon = "Military Spy";
			MPos = CFrame.new(-5815, 84, 8820);
			SP = "Default";
		elseif Sea2 then
			MMon = "Magma Ninja";
			MPos = CFrame.new(-5428, 78, -5959);
			SP = "Default";
		end
	elseif (SelectMaterial == "Angel Wings") then
		MMon = "God's Guard";
		MPos = CFrame.new(-4698, 845, -1912);
		SP = "Default";
		if ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(-7859.09814, 5544.19043, -381.476196)).Magnitude >= 5000) then
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-7859.09814, 5544.19043, -381.476196));
		end
	elseif (SelectMaterial == "Leather") then
		if Sea1 then
			MMon = "Brute";
			MPos = CFrame.new(-1145, 15, 4350);
			SP = "Default";
		elseif Sea2 then
			MMon = "Marine Captain";
			MPos = CFrame.new(-2010.5059814453125, 73.00115966796875, -3326.620849609375);
			SP = "Default";
		elseif Sea3 then
			MMon = "Jungle Pirate";
			MPos = CFrame.new(-11975.78515625, 331.7734069824219, -10620.0302734375);
			SP = "Default";
		end
	elseif (SelectMaterial == "Scrap Metal") then
		if Sea1 then
			MMon = "Brute";
			MPos = CFrame.new(-1145, 15, 4350);
			SP = "Default";
		elseif Sea2 then
			MMon = "Swan Pirate";
			MPos = CFrame.new(878, 122, 1235);
			SP = "Default";
		elseif Sea3 then
			MMon = "Jungle Pirate";
			MPos = CFrame.new(-12107, 332, -10549);
			SP = "Default";
		end
	elseif (SelectMaterial == "Fish Tail") then
		if Sea3 then
			MMon = "Fishman Raider";
			MPos = CFrame.new(-10993, 332, -8940);
			SP = "Default";
		elseif Sea1 then
			MMon = "Fishman Warrior";
			MPos = CFrame.new(61123, 19, 1569);
			SP = "Default";
			if ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(61163.8515625, 5.342342376708984, 1819.7841796875)).Magnitude >= 17000) then
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(61163.8515625, 5.342342376708984, 1819.7841796875));
			end
		end
	elseif (SelectMaterial == "Demonic Wisp") then
		MMon = "Demonic Soul";
		MPos = CFrame.new(-9507, 172, 6158);
		SP = "Default";
	elseif (SelectMaterial == "Vampire Fang") then
		MMon = "Vampire";
		MPos = CFrame.new(-6033, 7, -1317);
		SP = "Default";
	elseif (SelectMaterial == "Conjured Cocoa") then
		MMon = "Chocolate Bar Battler";
		MPos = CFrame.new(620.6344604492188, 78.93644714355469, -12581.369140625);
		SP = "Default";
	elseif (SelectMaterial == "Dragon Scale") then
		MMon = "Dragon Crew Archer";
		MPos = CFrame.new(6827.91455078125, 609.4127197265625, 252.3538055419922);
		SP = "Default";
	elseif (SelectMaterial == "Gunpowder") then
		MMon = "Pistol Billionaire";
		MPos = CFrame.new(-469, 74, 5904);
		SP = "Default";
	elseif (SelectMaterial == "Hydra Enforcer") then
		MMon = "Hydra Enforcer";
		MPos = CFrame.new(4581.517578125, 1001.55908203125, 704.9378662109375);
		SP = "Default";
	elseif (SelectMaterial == "Venomous Assailant") then
		MMon = "Venomous Assailant";
		MPos = CFrame.new(4879.92041015625, 1089.46142578125, 1104.00830078125);
		SP = "Default";
	elseif (SelectMaterial == "Mini Tusk") then
		MMon = "Mythological Pirate";
		MPos = CFrame.new();
		SP = "Default";
	end
end
function UpdateIslandESP()
	for i, v in pairs(game:GetService("Workspace")['_WorldOrigin'].Locations:GetChildren()) do
		pcall(function()
			if IslandESP then
				if (v.Name ~= "Sea") then
					if not v:FindFirstChild("NameEsp") then
						local bill = Instance.new("BillboardGui", v);
						bill.Name = "NameEsp";
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = "GothamBold";
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(8, 0, 0);
					else
						v['NameEsp'].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
					end
				end
			elseif v:FindFirstChild("NameEsp") then
				v:FindFirstChild("NameEsp"):Destroy();
			end
		end);
	end
end
function isnil(thing)
	return thing == nil;
end
local function round(n)
	return math.floor(tonumber(n) + 0.5);
end
Number = math.random(1, 1000000);
function UpdatePlayerChams()
	for i, v in pairs(game:GetService("Players"):GetChildren()) do
		pcall(function()
			if not isnil(v.Character) then
				if ESPPlayer then
					if (not isnil(v.Character.Head) and not v.Character.Head:FindFirstChild("NameEsp" .. Number)) then
						local bill = Instance.new("BillboardGui", v.Character.Head);
						bill.Name = "NameEsp" .. Number;
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v.Character.Head;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = Enum.Font.GothamSemibold;
						name.FontSize = "Size10";
						name.TextWrapped = true;
						name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Character.Head.Position).Magnitude / 3) .. " Distance";
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						if (v.Team == game.Players.LocalPlayer.Team) then
							name.TextColor3 = Color3.new(0, 0, 254);
						else
							name.TextColor3 = Color3.new(255, 0, 0);
						end
					else
						v.Character.Head["NameEsp" .. Number].TextLabel.Text = v.Name .. " | " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Character.Head.Position).Magnitude / 3) .. " Distance\nHealth : " .. round((v.Character.Humanoid.Health * 100) / v.Character.Humanoid.MaxHealth) .. "%";
					end
				elseif v.Character.Head:FindFirstChild("NameEsp" .. Number) then
					v.Character.Head:FindFirstChild("NameEsp" .. Number):Destroy();
				end
			end
		end);
	end
end
function UpdateChestChams()
	for i, v in pairs(game.Workspace:GetChildren()) do
		pcall(function()
			if string.find(v.Name, "Chest") then
				if ChestESP then
					if string.find(v.Name, "Chest") then
						if not v:FindFirstChild("NameEsp" .. Number) then
							local bill = Instance.new("BillboardGui", v);
							bill.Name = "NameEsp" .. Number;
							bill.ExtentsOffset = Vector3.new(0, 1, 0);
							bill.Size = UDim2.new(1, 200, 1, 30);
							bill.Adornee = v;
							bill.AlwaysOnTop = true;
							local name = Instance.new("TextLabel", bill);
							name.Font = Enum.Font.GothamSemibold;
							name.FontSize = "Size14";
							name.TextWrapped = true;
							name.Size = UDim2.new(1, 0, 1, 0);
							name.TextYAlignment = "Top";
							name.BackgroundTransparency = 1;
							name.TextStrokeTransparency = 0.5;
							if (v.Name == "Chest1") then
								name.TextColor3 = Color3.fromRGB(109, 109, 109);
								name.Text = "Chest 1" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							end
							if (v.Name == "Chest2") then
								name.TextColor3 = Color3.fromRGB(173, 158, 21);
								name.Text = "Chest 2" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							end
							if (v.Name == "Chest3") then
								name.TextColor3 = Color3.fromRGB(85, 255, 255);
								name.Text = "Chest 3" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							end
						else
							v["NameEsp" .. Number].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
						end
					end
				elseif v:FindFirstChild("NameEsp" .. Number) then
					v:FindFirstChild("NameEsp" .. Number):Destroy();
				end
			end
		end);
	end
end
function UpdateDevilChams()
	for i, v in pairs(game.Workspace:GetChildren()) do
		pcall(function()
			if DevilFruitESP then
				if string.find(v.Name, "Fruit") then
					if not v.Handle:FindFirstChild("NameEsp" .. Number) then
						local bill = Instance.new("BillboardGui", v.Handle);
						bill.Name = "NameEsp" .. Number;
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v.Handle;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = Enum.Font.GothamSemibold;
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(255, 255, 255);
						name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
					else
						v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
					end
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end);
	end
end
function UpdateFlowerChams()
	for i, v in pairs(game.Workspace:GetChildren()) do
		pcall(function()
			if ((v.Name == "Flower2") or (v.Name == "Flower1")) then
				if FlowerESP then
					if not v:FindFirstChild("NameEsp" .. Number) then
						local bill = Instance.new("BillboardGui", v);
						bill.Name = "NameEsp" .. Number;
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = Enum.Font.GothamSemibold;
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(255, 0, 0);
						if (v.Name == "Flower1") then
							name.Text = "Blue Flower" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							name.TextColor3 = Color3.fromRGB(0, 0, 255);
						end
						if (v.Name == "Flower2") then
							name.Text = "Red Flower" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							name.TextColor3 = Color3.fromRGB(255, 0, 0);
						end
					else
						v["NameEsp" .. Number].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
					end
				elseif v:FindFirstChild("NameEsp" .. Number) then
					v:FindFirstChild("NameEsp" .. Number):Destroy();
				end
			end
		end);
	end
end
function UpdateRealFruitChams()
	for i, v in pairs(game.Workspace.AppleSpawner:GetChildren()) do
		if v:IsA("Tool") then
			if RealFruitESP then
				if not v.Handle:FindFirstChild("NameEsp" .. Number) then
					local bill = Instance.new("BillboardGui", v.Handle);
					bill.Name = "NameEsp" .. Number;
					bill.ExtentsOffset = Vector3.new(0, 1, 0);
					bill.Size = UDim2.new(1, 200, 1, 30);
					bill.Adornee = v.Handle;
					bill.AlwaysOnTop = true;
					local name = Instance.new("TextLabel", bill);
					name.Font = Enum.Font.GothamSemibold;
					name.FontSize = "Size14";
					name.TextWrapped = true;
					name.Size = UDim2.new(1, 0, 1, 0);
					name.TextYAlignment = "Top";
					name.BackgroundTransparency = 1;
					name.TextStrokeTransparency = 0.5;
					name.TextColor3 = Color3.fromRGB(255, 0, 0);
					name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				else
					v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end
	end
	for i, v in pairs(game.Workspace.PineappleSpawner:GetChildren()) do
		if v:IsA("Tool") then
			if RealFruitESP then
				if not v.Handle:FindFirstChild("NameEsp" .. Number) then
					local bill = Instance.new("BillboardGui", v.Handle);
					bill.Name = "NameEsp" .. Number;
					bill.ExtentsOffset = Vector3.new(0, 1, 0);
					bill.Size = UDim2.new(1, 200, 1, 30);
					bill.Adornee = v.Handle;
					bill.AlwaysOnTop = true;
					local name = Instance.new("TextLabel", bill);
					name.Font = Enum.Font.GothamSemibold;
					name.FontSize = "Size14";
					name.TextWrapped = true;
					name.Size = UDim2.new(1, 0, 1, 0);
					name.TextYAlignment = "Top";
					name.BackgroundTransparency = 1;
					name.TextStrokeTransparency = 0.5;
					name.TextColor3 = Color3.fromRGB(255, 174, 0);
					name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				else
					v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end
	end
	for i, v in pairs(game.Workspace.BananaSpawner:GetChildren()) do
		if v:IsA("Tool") then
			if RealFruitESP then
				if not v.Handle:FindFirstChild("NameEsp" .. Number) then
					local bill = Instance.new("BillboardGui", v.Handle);
					bill.Name = "NameEsp" .. Number;
					bill.ExtentsOffset = Vector3.new(0, 1, 0);
					bill.Size = UDim2.new(1, 200, 1, 30);
					bill.Adornee = v.Handle;
					bill.AlwaysOnTop = true;
					local name = Instance.new("TextLabel", bill);
					name.Font = Enum.Font.GothamSemibold;
					name.FontSize = "Size14";
					name.TextWrapped = true;
					name.Size = UDim2.new(1, 0, 1, 0);
					name.TextYAlignment = "Top";
					name.BackgroundTransparency = 1;
					name.TextStrokeTransparency = 0.5;
					name.TextColor3 = Color3.fromRGB(251, 255, 0);
					name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				else
					v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end
	end
end
function UpdateIslandESP()
	for i, v in pairs(game:GetService("Workspace")['_WorldOrigin'].Locations:GetChildren()) do
		pcall(function()
			if IslandESP then
				if (v.Name ~= "Sea") then
					if not v:FindFirstChild("NameEsp") then
						local bill = Instance.new("BillboardGui", v);
						bill.Name = "NameEsp";
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = "GothamBold";
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(7, 236, 240);
					else
						v['NameEsp'].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
					end
				end
			elseif v:FindFirstChild("NameEsp") then
				v:FindFirstChild("NameEsp"):Destroy();
			end
		end);
	end
end
function isnil(thing)
	return thing == nil;
end
local function round(n)
	return math.floor(tonumber(n) + 0.5);
end
Number = math.random(1, 1000000);
function UpdatePlayerChams()
	for i, v in pairs(game:GetService("Players"):GetChildren()) do
		pcall(function()
			if not isnil(v.Character) then
				if ESPPlayer then
					if (not isnil(v.Character.Head) and not v.Character.Head:FindFirstChild("NameEsp" .. Number)) then
						local bill = Instance.new("BillboardGui", v.Character.Head);
						bill.Name = "NameEsp" .. Number;
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v.Character.Head;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = Enum.Font.GothamSemibold;
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Character.Head.Position).Magnitude / 3) .. " Distance";
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						if (v.Team == game.Players.LocalPlayer.Team) then
							name.TextColor3 = Color3.new(0, 255, 0);
						else
							name.TextColor3 = Color3.new(255, 0, 0);
						end
					else
						v.Character.Head["NameEsp" .. Number].TextLabel.Text = v.Name .. " | " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Character.Head.Position).Magnitude / 3) .. " Distance\nHealth : " .. round((v.Character.Humanoid.Health * 100) / v.Character.Humanoid.MaxHealth) .. "%";
					end
				elseif v.Character.Head:FindFirstChild("NameEsp" .. Number) then
					v.Character.Head:FindFirstChild("NameEsp" .. Number):Destroy();
				end
			end
		end);
	end
end
function UpdateChestChams()
	for i, v in pairs(game.Workspace:GetChildren()) do
		pcall(function()
			if string.find(v.Name, "Chest") then
				if ChestESP then
					if string.find(v.Name, "Chest") then
						if not v:FindFirstChild("NameEsp" .. Number) then
							local bill = Instance.new("BillboardGui", v);
							bill.Name = "NameEsp" .. Number;
							bill.ExtentsOffset = Vector3.new(0, 1, 0);
							bill.Size = UDim2.new(1, 200, 1, 30);
							bill.Adornee = v;
							bill.AlwaysOnTop = true;
							local name = Instance.new("TextLabel", bill);
							name.Font = Enum.Font.GothamSemibold;
							name.FontSize = "Size14";
							name.TextWrapped = true;
							name.Size = UDim2.new(1, 0, 1, 0);
							name.TextYAlignment = "Top";
							name.BackgroundTransparency = 1;
							name.TextStrokeTransparency = 0.5;
							if (v.Name == "Chest1") then
								name.TextColor3 = Color3.fromRGB(109, 109, 109);
								name.Text = "Chest 1" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							end
							if (v.Name == "Chest2") then
								name.TextColor3 = Color3.fromRGB(173, 158, 21);
								name.Text = "Chest 2" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							end
							if (v.Name == "Chest3") then
								name.TextColor3 = Color3.fromRGB(85, 255, 255);
								name.Text = "Chest 3" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							end
						else
							v["NameEsp" .. Number].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
						end
					end
				elseif v:FindFirstChild("NameEsp" .. Number) then
					v:FindFirstChild("NameEsp" .. Number):Destroy();
				end
			end
		end);
	end
end
function UpdateDevilChams()
	for i, v in pairs(game.Workspace:GetChildren()) do
		pcall(function()
			if DevilFruitESP then
				if string.find(v.Name, "Fruit") then
					if not v.Handle:FindFirstChild("NameEsp" .. Number) then
						local bill = Instance.new("BillboardGui", v.Handle);
						bill.Name = "NameEsp" .. Number;
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v.Handle;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = Enum.Font.GothamSemibold;
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(255, 255, 255);
						name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
					else
						v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
					end
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end);
	end
end
function UpdateFlowerChams()
	for i, v in pairs(game.Workspace:GetChildren()) do
		pcall(function()
			if ((v.Name == "Flower2") or (v.Name == "Flower1")) then
				if FlowerESP then
					if not v:FindFirstChild("NameEsp" .. Number) then
						local bill = Instance.new("BillboardGui", v);
						bill.Name = "NameEsp" .. Number;
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = Enum.Font.GothamSemibold;
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(255, 0, 0);
						if (v.Name == "Flower1") then
							name.Text = "Blue Flower" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							name.TextColor3 = Color3.fromRGB(0, 0, 255);
						end
						if (v.Name == "Flower2") then
							name.Text = "Red Flower" .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
							name.TextColor3 = Color3.fromRGB(255, 0, 0);
						end
					else
						v["NameEsp" .. Number].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " Distance";
					end
				elseif v:FindFirstChild("NameEsp" .. Number) then
					v:FindFirstChild("NameEsp" .. Number):Destroy();
				end
			end
		end);
	end
end
function UpdateRealFruitChams()
	for i, v in pairs(game.Workspace.AppleSpawner:GetChildren()) do
		if v:IsA("Tool") then
			if RealFruitESP then
				if not v.Handle:FindFirstChild("NameEsp" .. Number) then
					local bill = Instance.new("BillboardGui", v.Handle);
					bill.Name = "NameEsp" .. Number;
					bill.ExtentsOffset = Vector3.new(0, 1, 0);
					bill.Size = UDim2.new(1, 200, 1, 30);
					bill.Adornee = v.Handle;
					bill.AlwaysOnTop = true;
					local name = Instance.new("TextLabel", bill);
					name.Font = Enum.Font.GothamSemibold;
					name.FontSize = "Size14";
					name.TextWrapped = true;
					name.Size = UDim2.new(1, 0, 1, 0);
					name.TextYAlignment = "Top";
					name.BackgroundTransparency = 1;
					name.TextStrokeTransparency = 0.5;
					name.TextColor3 = Color3.fromRGB(255, 0, 0);
					name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				else
					v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end
	end
	for i, v in pairs(game.Workspace.PineappleSpawner:GetChildren()) do
		if v:IsA("Tool") then
			if RealFruitESP then
				if not v.Handle:FindFirstChild("NameEsp" .. Number) then
					local bill = Instance.new("BillboardGui", v.Handle);
					bill.Name = "NameEsp" .. Number;
					bill.ExtentsOffset = Vector3.new(0, 1, 0);
					bill.Size = UDim2.new(1, 200, 1, 30);
					bill.Adornee = v.Handle;
					bill.AlwaysOnTop = true;
					local name = Instance.new("TextLabel", bill);
					name.Font = Enum.Font.GothamSemibold;
					name.FontSize = "Size14";
					name.TextWrapped = true;
					name.Size = UDim2.new(1, 0, 1, 0);
					name.TextYAlignment = "Top";
					name.BackgroundTransparency = 1;
					name.TextStrokeTransparency = 0.5;
					name.TextColor3 = Color3.fromRGB(255, 174, 0);
					name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				else
					v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end
	end
	for i, v in pairs(game.Workspace.BananaSpawner:GetChildren()) do
		if v:IsA("Tool") then
			if RealFruitESP then
				if not v.Handle:FindFirstChild("NameEsp" .. Number) then
					local bill = Instance.new("BillboardGui", v.Handle);
					bill.Name = "NameEsp" .. Number;
					bill.ExtentsOffset = Vector3.new(0, 1, 0);
					bill.Size = UDim2.new(1, 200, 1, 30);
					bill.Adornee = v.Handle;
					bill.AlwaysOnTop = true;
					local name = Instance.new("TextLabel", bill);
					name.Font = Enum.Font.GothamSemibold;
					name.FontSize = "Size14";
					name.TextWrapped = true;
					name.Size = UDim2.new(1, 0, 1, 0);
					name.TextYAlignment = "Top";
					name.BackgroundTransparency = 1;
					name.TextStrokeTransparency = 0.5;
					name.TextColor3 = Color3.fromRGB(251, 255, 0);
					name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				else
					v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end
	end
end
spawn(function()
	while wait() do
		pcall(function()
			if MobESP then
				for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
					if v:FindFirstChild("HumanoidRootPart") then
						if not v:FindFirstChild("MobEap") then
							local BillboardGui = Instance.new("BillboardGui");
							local TextLabel = Instance.new("TextLabel");
							BillboardGui.Parent = v;
							BillboardGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling;
							BillboardGui.Active = true;
							BillboardGui.Name = "MobEap";
							BillboardGui.AlwaysOnTop = true;
							BillboardGui.LightInfluence = 1;
							BillboardGui.Size = UDim2.new(0, 200, 0, 50);
							BillboardGui.StudsOffset = Vector3.new(0, 2.5, 0);
							TextLabel.Parent = BillboardGui;
							TextLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255);
							TextLabel.BackgroundTransparency = 1;
							TextLabel.Size = UDim2.new(0, 200, 0, 50);
							TextLabel.Font = Enum.Font.GothamBold;
							TextLabel.TextColor3 = Color3.fromRGB(7, 236, 240);
							TextLabel.Text.Size = 35;
						end
						local Dis = math.floor((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - v.HumanoidRootPart.Position).Magnitude);
						v.MobEap.TextLabel.Text = v.Name .. "-" .. Dis .. " Distance";
					end
				end
			else
				for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
					if v:FindFirstChild("MobEap") then
						v.MobEap:Destroy();
					end
				end
			end
		end);
	end
end);
spawn(function()
	while wait() do
		pcall(function()
			if SeaESP then
				for i, v in pairs(game:GetService("Workspace").SeaBeasts:GetChildren()) do
					if v:FindFirstChild("HumanoidRootPart") then
						if not v:FindFirstChild("Seaesps") then
							local BillboardGui = Instance.new("BillboardGui");
							local TextLabel = Instance.new("TextLabel");
							BillboardGui.Parent = v;
							BillboardGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling;
							BillboardGui.Active = true;
							BillboardGui.Name = "Seaesps";
							BillboardGui.AlwaysOnTop = true;
							BillboardGui.LightInfluence = 1;
							BillboardGui.Size = UDim2.new(0, 200, 0, 50);
							BillboardGui.StudsOffset = Vector3.new(0, 2.5, 0);
							TextLabel.Parent = BillboardGui;
							TextLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255);
							TextLabel.BackgroundTransparency = 1;
							TextLabel.Size = UDim2.new(0, 200, 0, 50);
							TextLabel.Font = Enum.Font.GothamBold;
							TextLabel.TextColor3 = Color3.fromRGB(7, 236, 240);
							TextLabel.Text.Size = 35;
						end
						local Dis = math.floor((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - v.HumanoidRootPart.Position).Magnitude);
						v.Seaesps.TextLabel.Text = v.Name .. "-" .. Dis .. " Distance";
					end
				end
			else
				for i, v in pairs(game:GetService("Workspace").SeaBeasts:GetChildren()) do
					if v:FindFirstChild("Seaesps") then
						v.Seaesps:Destroy();
					end
				end
			end
		end);
	end
end);
spawn(function()
	while wait() do
		pcall(function()
			if NpcESP then
				for i, v in pairs(game:GetService("Workspace").NPCs:GetChildren()) do
					if v:FindFirstChild("HumanoidRootPart") then
						if not v:FindFirstChild("NpcEspes") then
							local BillboardGui = Instance.new("BillboardGui");
							local TextLabel = Instance.new("TextLabel");
							BillboardGui.Parent = v;
							BillboardGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling;
							BillboardGui.Active = true;
							BillboardGui.Name = "NpcEspes";
							BillboardGui.AlwaysOnTop = true;
							BillboardGui.LightInfluence = 1;
							BillboardGui.Size = UDim2.new(0, 200, 0, 50);
							BillboardGui.StudsOffset = Vector3.new(0, 2.5, 0);
							TextLabel.Parent = BillboardGui;
							TextLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255);
							TextLabel.BackgroundTransparency = 1;
							TextLabel.Size = UDim2.new(0, 200, 0, 50);
							TextLabel.Font = Enum.Font.GothamBold;
							TextLabel.TextColor3 = Color3.fromRGB(7, 236, 240);
							TextLabel.Text.Size = 35;
						end
						local Dis = math.floor((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - v.HumanoidRootPart.Position).Magnitude);
						v.NpcEspes.TextLabel.Text = v.Name .. "-" .. Dis .. " Distance";
					end
				end
			else
				for i, v in pairs(game:GetService("Workspace").NPCs:GetChildren()) do
					if v:FindFirstChild("NpcEspes") then
						v.NpcEspes:Destroy();
					end
				end
			end
		end);
	end
end);
function isnil(thing)
	return thing == nil;
end
local function round(n)
	return math.floor(tonumber(n) + 0.5);
end
Number = math.random(1, 1000000);
function UpdateIslandMirageESP()
	for i, v in pairs(game:GetService("Workspace")['_WorldOrigin'].Locations:GetChildren()) do
		pcall(function()
			if MirageIslandESP then
				if (v.Name == "Mirage Island") then
					if not v:FindFirstChild("NameEsp") then
						local bill = Instance.new("BillboardGui", v);
						bill.Name = "NameEsp";
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = "Code";
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(80, 245, 245);
					else
						v['NameEsp'].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " M";
					end
				end
			elseif v:FindFirstChild("NameEsp") then
				v:FindFirstChild("NameEsp"):Destroy();
			end
		end);
	end
end
function UpdateAuraESP()
	for i, v in pairs(game:GetService("Workspace").NPCs:GetChildren()) do
		pcall(function()
			if AuraESP then
				if (v.Name == "Master of Enhancement") then
					if not v:FindFirstChild("NameEsp") then
						local bill = Instance.new("BillboardGui", v);
						bill.Name = "NameEsp";
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = "Code";
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(80, 245, 245);
					else
						v['NameEsp'].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " M";
					end
				end
			elseif v:FindFirstChild("NameEsp") then
				v:FindFirstChild("NameEsp"):Destroy();
			end
		end);
	end
end
function UpdateLSDESP()
	for i, v in pairs(game:GetService("Workspace").NPCs:GetChildren()) do
		pcall(function()
			if LADESP then
				if (v.Name == "Legendary Sword Dealer") then
					if not v:FindFirstChild("NameEsp") then
						local bill = Instance.new("BillboardGui", v);
						bill.Name = "NameEsp";
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = "Code";
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(80, 245, 245);
					else
						v['NameEsp'].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " M";
					end
				end
			elseif v:FindFirstChild("NameEsp") then
				v:FindFirstChild("NameEsp"):Destroy();
			end
		end);
	end
end
function UpdateGeaESP()
	for i, v in pairs(game:GetService("Workspace").Map.MysticIsland:GetChildren()) do
		pcall(function()
			if GearESP then
				if (v.Name == "MeshPart") then
					if not v:FindFirstChild("NameEsp") then
						local bill = Instance.new("BillboardGui", v);
						bill.Name = "NameEsp";
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = "Code";
						name.FontSize = "Size14";
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = "Top";
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(80, 245, 245);
					else
						v['NameEsp'].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " M";
					end
				end
			elseif v:FindFirstChild("NameEsp") then
				v:FindFirstChild("NameEsp"):Destroy();
			end
		end);
	end
end
function Tween2(P1)
	local Distance = (P1.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude;
	local Speed = 350;
	if (Distance >= 350) then
		Speed = 350;
	end
	local tweenInfo = TweenInfo.new(Distance / Speed, Enum.EasingStyle.Linear);
	local tween = game:GetService("TweenService"):Create(game.Players.LocalPlayer.Character.HumanoidRootPart, tweenInfo, {CFrame=P1});
	tween:Play();
	if _G.CancelTween2 then
		tween:Cancel();
	end
	_G.Clip2 = true;
	wait(Distance / Speed);
	_G.Clip2 = false;
end
function BTPZ(Point)
	game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = Point;
	task.wait();
	game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = Point;
end
TweenSpeed = 350;
function Tween(P1)
	local Distance = (P1.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude;
	local Speed = TweenSpeed;
	if (Distance >= 350) then
		Speed = TweenSpeed;
	end
	local tweenInfo = TweenInfo.new(Distance / Speed, Enum.EasingStyle.Linear);
	local tween = game:GetService("TweenService"):Create(game.Players.LocalPlayer.Character.HumanoidRootPart, tweenInfo, {CFrame=P1});
	tween:Play();
	if _G.StopTween then
		tween:Cancel();
	end
end
function CancelTween(target)
	if not target then
		_G.StopTween = true;
		wait();
		Tween(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame);
		wait();
		_G.StopTween = false;
	end
end
function EquipTool(ToolSe)
	if game.Players.LocalPlayer.Backpack:FindFirstChild(ToolSe) then
		local tool = game.Players.LocalPlayer.Backpack:FindFirstChild(ToolSe);
		wait();
		game.Players.LocalPlayer.Character.Humanoid:EquipTool(tool);
	end
end
spawn(function()
	local gg = getrawmetatable(game);
	local old = gg.__namecall;
	setreadonly(gg, false);
	gg.__namecall = newcclosure(function(...)
		local method = getnamecallmethod();
		local args = {...};
		if (tostring(method) == "FireServer") then
			if (tostring(args[1]) == "RemoteEvent") then
				if ((tostring(args[2]) ~= "true") and (tostring(args[2]) ~= "false")) then
					if _G.UseSkill then
						if (type(args[2]) == "vector") then
							args[2] = PositionSkillMasteryDevilFruit;
						else
							args[2] = CFrame.new(PositionSkillMasteryDevilFruit);
						end
						return old(unpack(args));
					end
				end
			end
		end
		return old(...);
	end);
end);
spawn(function()
	while task.wait() do
		pcall(function()
			if (_G.AutoEvoRace or _G.CastleRaid or _G.CollectAzure or _G.TweenToKitsune or _G.GhostShip or _G.Ship or _G.Auto_Holy_Torch or _G.TeleportPly or _G.Auto_Sea3 or _G.Auto_Sea2 or _G.Tweenfruit or _G.AutoFishCrew or _G.Auto_Saber or _G.AutoShark or _G.Auto_Warden or _G.Auto_RainbowHaki or AutoFarmRace or _G.AutoQuestRace or Auto_Law or AutoTushita or _G.AutoHolyTorch or _G.AutoTerrorshark or _G.farmpiranya or _G.Auto_MusketeerHat or _G.Auto_ObservationV2 or _G.AutoNear or _G.Auto_PoleV1 or _G.Auto_Buddy or _G.Ectoplasm or AutoEvoRace or AutoBartilo or _G.Auto_Canvander or _G.AutoLevel or _G.SummerToken or _G.Auto_DualKatana or Auto_Quest_Yama_3 or Auto_Quest_Yama_2 or Auto_Quest_Yama_1 or Auto_Quest_Tushita_1 or Auto_Quest_Tushita_2 or Auto_Quest_Tushita_3 or _G.Clip2 or _G.Auto_Regoku or _G.AutoBone or _G.AutoBoneNoQuest or _G.AutoBoss or AutoFarmMasDevilFruit or AutoHallowSycthe or AutoTushita or _G.CakePrince or _G.Auto_SkullGuitar or _G.AutoFarmSwan or _G.DoughKing or _G.AutoEliteor or AutoNextIsland or Musketeer or _G.AutoMaterial or AutoFarmRaceQuest or _G.Factory or _G.Auto_Saw or _G.AutoFrozenDimension or _G.AutoKillTrial or _G.AutoUpgrade or _G.TweenToFrozenDimension) then
				if not game:GetService("Players").LocalPlayer.Character.HumanoidRootPart:FindFirstChild("BodyClip") then
					local Noclip = Instance.new("BodyVelocity");
					Noclip.Name = "BodyClip";
					Noclip.Parent = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart;
					Noclip.MaxForce = Vector3.new(100000, 100000, 100000);
					Noclip.Velocity = Vector3.new(0, 0, 0);
				end
			else
				game:GetService("Players").LocalPlayer.Character.HumanoidRootPart:FindFirstChild("BodyClip"):Destroy();
			end
		end);
	end
end);
spawn(function()
	pcall(function()
		game:GetService("RunService").Stepped:Connect(function()
			if (_G.AutoEvoRace or _G.Auto_RainbowHaki or _G.Auto_SkullGuitar or _G.CastleRaid or _G.CollectAzure or _G.TweenToKitsune or _G.Auto_Sea3 or _G.Auto_Sea2 or _G.GhostShip or _G.Ship or _G.Auto_Holy_Torch or _G.TeleportPly or _G.Tweenfruit or _G.Auto_Saber or _G.Auto_PoleV1 or _G.Auto_MusketeerHat or _G.AutoFishCrew or _G.AutoShark or AutoFarmRace or _G.AutoQuestRace or _G.Auto_Warden or Auto_Law or _G.Auto_DualKatana or Auto_Quest_Tushita_1 or Auto_Quest_Tushita_2 or Auto_Quest_Tushita_3 or AutoTushita or _G.AutoHolyTorch or _G.Auto_Buddy or _G.AutoTerrorshark or _G.SummerToken or _G.farmpiranya or Auto_Quest_Yama_3 or _G.Auto_ObservationV2 or Auto_Quest_Yama_2 or Auto_Quest_Yama_1 or _G.AutoNear or _G.Ectoplasm or AutoEvoRace or _G.AutoKillTrial or AutoBartilo or _G.Auto_Regoku or _G.AutoLevel or _G.Clip2 or _G.AutoBone or _G.Auto_Canvander or _G.AutoBoneNoQuest or _G.AutoBoss or _G.Auto_Saw or AutoFarmMasDevilFruit or AutoHallowSycthe or AutoTushita or _G.CakePrince or _G.DoughKing or _G.AutoFarmSwan or _G.AutoEliteor or AutoNextIsland or Musketeer or _G.AutoMaterial or _G.Factory or _G.AutoFrozenDimension or AutoFarmRaceQuest or _G.AutoUpgrade or _G.TweenToFrozenDimension) then
				for i, v in pairs(game:GetService("Players").LocalPlayer.Character:GetDescendants()) do
					if v:IsA("BasePart") then
						v.CanCollide = false;
					end
				end
			end
		end);
	end);
end);
task.spawn(function()
	if game.Players.LocalPlayer.Character:FindFirstChild("Stun") then
		game.Players.LocalPlayer.Character.Stun.Changed:connect(function()
			pcall(function()
				if game.Players.LocalPlayer.Character:FindFirstChild("Stun") then
					game.Players.LocalPlayer.Character.Stun.Value = 0;
				end
			end);
		end);
	end
end);
function CheckMaterial(matname)
	for i, v in pairs(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("getInventory")) do
		if (type(v) == "table") then
			if (v.Type == "Material") then
				if (v.Name == matname) then
					return v.Count;
				end
			end
		end
	end
	return 0;
end
function GetWeaponInventory(Weaponname)
	for i, v in pairs(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("getInventory")) do
		if (type(v) == "table") then
			if (v.Type == "Sword") then
				if (v.Name == Weaponname) then
					return true;
				end
			end
		end
	end
	return false;
end
Type = 1;
spawn(function()
	while wait() do
		if (Type == 1) then
			Pos = CFrame.new(0, 40, 0);
		elseif (Type == 2) then
			Pos = CFrame.new(-40, 40, 0);
		elseif (Type == 3) then
			Pos = CFrame.new(40, 40, 0);
		elseif (Type == 4) then
			Pos = CFrame.new(0, 40, 40);
		elseif (Type == 5) then
			Pos = CFrame.new(0, 40, -40);
		end
	end
end);
spawn(function()
	while wait() do
		Type = 1;
		wait(0.2);
		Type = 2;
		wait(0.2);
		Type = 3;
		wait(0.2);
		Type = 4;
		wait(0.2);
		Type = 5;
		wait(0.2);
	end
end);
function AutoHaki()
	if not game:GetService("Players").LocalPlayer.Character:FindFirstChild("HasBuso") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Buso");
	end
end
function to(P)
	repeat
		wait(_G.Fast_Delay);
		game.Players.LocalPlayer.Character.Humanoid:ChangeState(15);
		game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = P;
		task.wait();
		game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = P;
	until (P.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 2000 
end
function to(p)
	pcall(function()
		if (((p.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude >= 2000) and not Auto_Raid and (game.Players.LocalPlayer.Character.Humanoid.Health > 0)) then
			if (NameMon == "FishmanQuest") then
				Tween(game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame);
				wait();
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(61163.8515625, 11.6796875, 1819.7841796875));
			elseif (Mon == "God's Guard") then
				Tween(game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame);
				wait();
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-4607.82275, 872.54248, -1667.55688));
			elseif (NameMon == "SkyExp1Quest") then
				Tween(game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame);
				wait();
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-7894.6176757813, 5547.1416015625, -380.29119873047));
			elseif (NameMon == "ShipQuest1") then
				Tween(game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame);
				wait();
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(923.21252441406, 126.9760055542, 32852.83203125));
			elseif (NameMon == "ShipQuest2") then
				Tween(game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame);
				wait();
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(923.21252441406, 126.9760055542, 32852.83203125));
			elseif (NameMon == "FrostQuest") then
				Tween(game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame);
				wait();
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-6508.5581054688, 89.034996032715, -132.83953857422));
			else
				repeat
					wait(_G.Fast_Delay);
					game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = p;
					wait(0.05);
					game.Players.LocalPlayer.Character.Head:Destroy();
					game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = p;
				until ((p.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude < 2500) and (game.Players.LocalPlayer.Character.Humanoid.Health > 0) 
				wait();
			end
		end
	end);
end
local ScreenGui = Instance.new("ScreenGui");
local ImageButton = Instance.new("ImageButton");
local UICorner = Instance.new("UICorner");
local ParticleEmitter = Instance.new("ParticleEmitter");
local TweenService = game:GetService("TweenService");
ScreenGui.Parent = game.CoreGui;
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling;
ImageButton.Parent = ScreenGui;
ImageButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0);
ImageButton.BorderSizePixel = 0;
ImageButton.Position = UDim2.new(0.120833337 - 0.1, 0, 0.0952890813 + 0.01, 0);
ImageButton.Size = UDim2.new(0, 50, 0, 50);
ImageButton.Draggable = true;
ImageButton.Image = "http://www.roblox.com/asset/?id=88708608862647";
UICorner.Parent = ImageButton;
UICorner.CornerRadius = UDim.new(0, 12);
ParticleEmitter.Parent = ImageButton;
ParticleEmitter.LightEmission = 1;
ParticleEmitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1),NumberSequenceKeypoint.new(1, 0)});
ParticleEmitter.Lifetime = NumberRange.new(0.5, 1);
ParticleEmitter.Rate = 0;
ParticleEmitter.Speed = NumberRange.new(5, 10);
ParticleEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 85, 255), Color3.fromRGB(85, 255, 255));
local rotateTween = TweenService:Create(ImageButton, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation=360});
ImageButton.MouseButton1Down:Connect(function()
	game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.End, false, game);
end);
if game:GetService("ReplicatedStorage").Effect.Container:FindFirstChild("Death") then
	game:GetService("ReplicatedStorage").Effect.Container.Death:Destroy();
end
if game:GetService("ReplicatedStorage").Effect.Container:FindFirstChild("Respawn") then
	game:GetService("ReplicatedStorage").Effect.Container.Respawn:Destroy();
end

Tabs.Home:AddButton({
    Title = "Discord Nhà Phát Triển",
    Description = "",
    Callback = function()
        setclipboard("https://discord.com/invite/hcJ8PHtkfy") 
    end
})

_G.FastAttackStrix_Mode = "Super Fast Attack";
spawn(function()
	while wait() do
		if _G.FastAttackStrix_Mode then
			pcall(function()
				if (_G.FastAttackStrix_Mode == "Super Fast Attack") then
					_G.Fast_Delay = 1e-9;
				end
			end);
		end
	end
end);
local DropdownSelectWeapon = Tabs.Main:AddDropdown("DropdownSelectWeapon", {Title="Vũ Khí",Description="",Values={"Melee","Sword","Blox Fruits"},Multi=false,Default=1});
DropdownSelectWeapon:SetValue("Melee");
DropdownSelectWeapon:OnChanged(function(Value)
	ChooseWeapon = Value;
end);
task.spawn(function()
	while wait() do
		pcall(function()
			if (ChooseWeapon == "Melee") then
				for _, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
					if (v.ToolTip == "Melee") then
						if game.Players.LocalPlayer.Backpack:FindFirstChild(tostring(v.Name)) then
							SelectWeapon = v.Name;
						end
					end
				end
			elseif (ChooseWeapon == "Sword") then
				for _, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
					if (v.ToolTip == "Sword") then
						if game.Players.LocalPlayer.Backpack:FindFirstChild(tostring(v.Name)) then
							SelectWeapon = v.Name;
						end
					end
				end
			elseif (ChooseWeapon == "Blox Fruit") then
				for _, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
					if (v.ToolTip == "Blox Fruit") then
						if game.Players.LocalPlayer.Backpack:FindFirstChild(tostring(v.Name)) then
							SelectWeapon = v.Name;
						end
					end
				end
			end
		end);
	end
end);
local ToggleLevel = Tabs.Main:AddToggle("ToggleLevel", {Title="Cày Cấp",Description="",Default=false});
ToggleLevel:OnChanged(function(Value)
	_G.AutoLevel = Value;
	if (Value == false) then
		wait();
		Tween(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame);
		wait();
	end
end);
Options.ToggleLevel:SetValue(false);
spawn(function()
    while wait() do
        if _G.AutoLevel then
            pcall(function()
                local QuestTitle = game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text
                CheckQuest()
                if not string.find(QuestTitle, NameMon) then
                    bringmob = false
                    game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("AbandonQuest")
                end
                if game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == false then
                    bringmob = false
                    if BypassTP then
                        if (game.Players.LocalPlayer.Character.HumanoidRootPart.Position - CFrameQuest.Position).Magnitude > 1500 then
                            Tween(CFrameQuest)
                        elseif (game.Players.LocalPlayer.Character.HumanoidRootPart.Position - CFrameQuest.Position).Magnitude < 1500 then
                            Tween(CFrameQuest)
                        end
                    else
                        Tween(CFrameQuest)
                    end
                    if (game.Players.LocalPlayer.Character.HumanoidRootPart.Position - CFrameQuest.Position).Magnitude <= 20 then
                        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StartQuest", NameQuest, LevelQuest)
                    end
                elseif game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == true then
                    if string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "kissed") then
                        for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
                            if string.find(v.Name, "kissed Warrior") then
                                if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                                    if string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, NameMon) then
                                        repeat
                                            task.wait()
                                            bringmob = true;
				                			AutoHaki();
				                			EquipTool(SelectWeapon);
                                            Tween(v.HumanoidRootPart.CFrame * CFrame.new(0, 30, 0))
                                            v.HumanoidRootPart.CanCollide = false
                                            v.Humanoid.WalkSpeed = 0
                                            v.Head.CanCollide = false
                                            FarmPos = v.HumanoidRootPart.CFrame;
					                		MonFarm = v.Name;
                                        until not _G.AutoLevel or v.Humanoid.Health <= 0 or not v.Parent or game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == false
                                    else
                                        bringmob = false
                                        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("AbandonQuest")
                                    end
                                end
                            elseif string.find(v.Name, "kissed Warrior") == nil then
                                Tween(CFrameMon)
                                bringmob = false
                                if game:GetService("ReplicatedStorage"):FindFirstChild(Mon) then
                                    Tween(game:GetService("ReplicatedStorage"):FindFirstChild(Mon).HumanoidRootPart.CFrame * CFrame.new(0, 20, 0))
                                end
                            end
                        end
                    else
                        if game:GetService("Workspace").Enemies:FindFirstChild(Mon) then
                            for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
                                if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                                    if v.Name == Mon then
                                        if string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, NameMon) then
                                            repeat
                                                task.wait()
                                                bringmob = true;
			                        			AutoHaki();
			                        			EquipTool(SelectWeapon);
                                                Tween(v.HumanoidRootPart.CFrame * CFrame.new(0, 30, 0))
                                                v.HumanoidRootPart.CanCollide = false
                                                v.Humanoid.WalkSpeed = 0
                                                v.Head.CanCollide = false
                                                FarmPos = v.HumanoidRootPart.CFrame;
				                        		MonFarm = v.Name;
                                            until not _G.AutoLevel or v.Humanoid.Health <= 0 or not v.Parent or game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == false
                                        else
                                            bringmob = false
                                            game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("AbandonQuest")
                                        end
                                    end
                                end
                            end
                        else
                            Tween(CFrameMon)
                            bringmob = false
                            if game:GetService("ReplicatedStorage"):FindFirstChild(Mon) then
                                Tween(game:GetService("ReplicatedStorage"):FindFirstChild(Mon).HumanoidRootPart.CFrame * CFrame.new(0, 20, 0))
                            end
                        end
                    end
                end
            end)
        end
    end
end)
local ToggleMobAura = Tabs.Main:AddToggle("ToggleMobAura", {Title="Đấm Quái Gần",Description="",Default=false});
ToggleMobAura:OnChanged(function(Value)
	_G.AutoNear = Value;
	if (Value == false) then
		wait();
		Tween(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame);
		wait();
	end
end);
Options.ToggleMobAura:SetValue(false);
spawn(function()
	while wait() do
		if _G.AutoNear then
			pcall(function()
				for i, v in pairs(game.Workspace.Enemies:GetChildren()) do
					if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
						if v.Name then
							if ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - v:FindFirstChild("HumanoidRootPart").Position).Magnitude <= 5000) then
								repeat
									wait(_G.Fast_Delay);
									AttackNoCoolDown();
									bringmob = true;
									AutoHaki();
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
									v.HumanoidRootPart.Transparency = 1;
									v.Humanoid.JumpPower = 0;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.CanCollide = false;
									FarmPos = v.HumanoidRootPart.CFrame;
									MonFarm = v.Name;
								until not _G.AutoNear or not v.Parent or (v.Humanoid.Health <= 0) or not game.Workspace.Enemies:FindFirstChild(v.Name) 
								bringmob = false;
							end
						end
					end
				end
			end);
		end
	end
end);
local ToggleCastleRaid = Tabs.Main:AddToggle("ToggleCastleRaid", {Title="Đấm Hải Tặc",Description="",Default=false});
ToggleCastleRaid:OnChanged(function(Value)
	_G.CastleRaid = Value;
end);
Options.ToggleCastleRaid:SetValue(false);
spawn(function()
	while wait() do
		if _G.CastleRaid then
			pcall(function()
				local CFrameCastleRaid = CFrame.new(-5496.17432, 313.768921, -2841.53027, 0.924894512, 7.37058e-9, 0.380223751, 3.588102e-8, 1, -1.06665446e-7, -0.380223751, 1.1229711e-7, 0.924894512);
				if ((CFrame.new(-5539.3115234375, 313.800537109375, -2972.372314453125).Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 500) then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (_G.CastleRaid and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and (v.Humanoid.Health > 0)) then
							if ((v.HumanoidRootPart.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude < 2000) then
								repeat
									wait(_G.Fast_Delay);
									AttackNoCoolDown();
									AutoHaki();
									EquipTool(SelectWeapon);
									v.HumanoidRootPart.CanCollide = false;
									v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
									Tween(v.HumanoidRootPart.CFrame * Pos);
								until (v.Humanoid.Health <= 0) or not v.Parent or not _G.CastleRaid 
							end
						end
					end
				else
					Tween(CFrameCastleRaid);
				end
			end);
		end
	end
end);
local ToggleHakiFortress = Tabs.Main:AddToggle("ToggleHakiFortress", {Title="Bật Haki Màu Pháo Đài",Description="",Default=false});
ToggleHakiFortress:OnChanged(function(Value)
	_G.EnableHakiFortress = Value;
end);
Options.ToggleHakiFortress:SetValue(false);
local function EquipAuraAndTeleport(storageName, targetPosition)
	local args = {[1]={StorageName=storageName,Type="AuraSkin",Context="Equip"}};
	game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/FruitCustomizerRF"):InvokeServer(unpack(args));
	Tween2(targetPosition);
end
local function IsAtPosition(targetPosition, tolerance)
	local character = game.Players.LocalPlayer.Character;
	if (not character or not character:FindFirstChild("HumanoidRootPart")) then
		return false;
	end
	local characterPosition = character.HumanoidRootPart.Position;
	return (characterPosition - targetPosition).Magnitude < tolerance;
end
spawn(function()
	while true do
		if _G.EnableHakiFortress then
			EquipAuraAndTeleport("Snow White", Vector3.new(-4971.71826171875, 335.9582214355469, -3720.0595703125));
			while not IsAtPosition(Vector3.new(-4971.71826171875, 335.9582214355469, -3720.0595703125), 1) do
				wait(0.1);
			end
			wait(0.5);
			EquipAuraAndTeleport("Pure Red", Vector3.new(-5414.92041015625, 314.2582092285156, -2212.20166015625));
			while not IsAtPosition(Vector3.new(-5414.92041015625, 314.2582092285156, -2212.20166015625), 1) do
				wait(0.1);
			end
			wait(0.5);
			EquipAuraAndTeleport("Winter Sky", Vector3.new(-5420.26318359375, 1089.3582763671875, -2666.8193359375));
			while not IsAtPosition(Vector3.new(-5420.26318359375, 1089.3582763671875, -2666.8193359375), 1) do
				wait(0.1);
			end
			wait(0.5);
			_G.EnableHakiFortress = false;
		end
		wait(0.5);
	end
end);
local ToggleCollectChest = Tabs.Main:AddToggle("ToggleCollectChest", {Title="Lụm Rương",Description="",Default=false});
ToggleCollectChest:OnChanged(function(Value)
	_G.AutoCollectChest = Value;
end);
spawn(function()
	while wait() do
		if _G.AutoCollectChest then
			local Players = game:GetService("Players");
			local Player = Players.LocalPlayer;
			local Character = Player.Character or Player.CharacterAdded:Wait();
			local Position = Character:GetPivot().Position;
			local CollectionService = game:GetService("CollectionService");
			local Chests = CollectionService:GetTagged("_ChestTagged");
			local Distance, Nearest = math.huge;
			for i = 1, #Chests do
				local Chest = Chests[i];
				local Magnitude = (Chest:GetPivot().Position - Position).Magnitude;
				if (not Chest:GetAttribute("IsDisabled") and (Magnitude < Distance)) then
					Distance, Nearest = Magnitude, Chest;
				end
			end
			if Nearest then
				local ChestPosition = Nearest:GetPivot().Position;
				local CFrameTarget = CFrame.new(ChestPosition);
				Tween2(CFrameTarget);
			end
		end
	end
end);
local Mastery = Tabs.Main:AddSection("Thông Thạo");
local DropdownMastery = Tabs.Main:AddDropdown("DropdownMastery", {Title="Cày Thông Thạo",Description="",Values={"Near Mobs"},Multi=false,Default=1});
DropdownMastery:SetValue(TypeMastery);
DropdownMastery:OnChanged(function(Value)
	TypeMastery = Value;
end);
local ToggleMasteryFruit = Tabs.Main:AddToggle("ToggleMasteryFruit", {Title="Cày Trái",Description="",Default=false});
ToggleMasteryFruit:OnChanged(function(Value)
	AutoFarmMasDevilFruit = Value;
end);
Options.ToggleMasteryFruit:SetValue(false);
local SliderHealt = Tabs.Main:AddSlider("SliderHealt", {Title="Máu Quái",Description="",Default=20,Min=0,Max=100,Rounding=1,Callback=function(Value)
	KillPercent = Value;
end});
SliderHealt:OnChanged(function(Value)
	KillPercent = Value;
end);
SliderHealt:SetValue(20);
spawn(function()
	while task.wait() do
		if _G.UseSkill then
			pcall(function()
				if _G.UseSkill then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if ((v.Name == MonFarm) and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health <= ((v.Humanoid.MaxHealth * KillPercent) / 100))) then
							repeat
								game:GetService("RunService").Heartbeat:wait();
								EquipTool(game.Players.LocalPlayer.Data.DevilFruit.Value);
								Tween(v.HumanoidRootPart.CFrame * Pos);
								PositionSkillMasteryDevilFruit = v.HumanoidRootPart.Position;
								if game:GetService("Players").LocalPlayer.Character:FindFirstChild(game.Players.LocalPlayer.Data.DevilFruit.Value) then
									game:GetService("Players").LocalPlayer.Character:FindFirstChild(game.Players.LocalPlayer.Data.DevilFruit.Value).MousePos.Value = PositionSkillMasteryDevilFruit;
									local DevilFruitMastery = game:GetService("Players").LocalPlayer.Character:FindFirstChild(game.Players.LocalPlayer.Data.DevilFruit.Value).Level.Value;
									if (SkillZ and (DevilFruitMastery >= 1)) then
										game:service("VirtualInputManager"):SendKeyEvent(true, "Z", false, game);
										wait();
										game:service("VirtualInputManager"):SendKeyEvent(false, "Z", false, game);
									end
									if (SkillX and (DevilFruitMastery >= 2)) then
										game:service("VirtualInputManager"):SendKeyEvent(true, "X", false, game);
										wait();
										game:service("VirtualInputManager"):SendKeyEvent(false, "X", false, game);
									end
									if (SkillC and (DevilFruitMastery >= 3)) then
										game:service("VirtualInputManager"):SendKeyEvent(true, "C", false, game);
										wait();
										game:service("VirtualInputManager"):SendKeyEvent(false, "C", false, game);
									end
									if (SkillV and (DevilFruitMastery >= 4)) then
										game:service("VirtualInputManager"):SendKeyEvent(true, "V", false, game);
										wait();
										game:service("VirtualInputManager"):SendKeyEvent(false, "V", false, game);
									end
									if (SkillF and (DevilFruitMastery >= 5)) then
										game:GetService("VirtualInputManager"):SendKeyEvent(true, "F", false, game);
										wait();
										game:GetService("VirtualInputManager"):SendKeyEvent(false, "F", false, game);
									end
								end
							until not AutoFarmMasDevilFruit or not _G.UseSkill or (v.Humanoid.Health == 0) 
						end
					end
				end
			end);
		end
	end
end);
spawn(function()
	while task.wait(0.1) do
		if (AutoFarmMasDevilFruit and (TypeMastery == "Near Mobs")) then
			pcall(function()
				for i, v in pairs(game.Workspace.Enemies:GetChildren()) do
					if (v.Name and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart")) then
						if ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - v:FindFirstChild("HumanoidRootPart").Position).Magnitude <= 5000) then
							repeat
								wait(_G.Fast_Delay);
								if (v.Humanoid.Health <= ((v.Humanoid.MaxHealth * KillPercent) / 100)) then
									_G.UseSkill = true;
								else
									_G.UseSkill = false;
									AutoHaki();
									bringmob = true;
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
									v.HumanoidRootPart.Transparency = 1;
									v.Humanoid.JumpPower = 0;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.CanCollide = false;
									FarmPos = v.HumanoidRootPart.CFrame;
									MonFarm = v.Name;
									AttackNoCoolDown();
								end
							until not AutoFarmMasDevilFruit or (not MasteryType == "Near Mobs") or not v.Parent or (v.Humanoid.Health == 0) 
							bringmob = false;
							_G.UseSkill = false;
						end
					end
				end
			end);
		end
	end
end);
if Sea3 then
	local MiscFarm = Tabs.Main:AddSection("Xương");
	local StatusBone = Tabs.Main:AddParagraph({Title="Xương Trạng Thái",Content=""});
	spawn(function()
		pcall(function()
			while wait() do
				local bones = game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Bones", "Check");
				StatusBone:SetDesc("Mày Có: " .. tostring(bones) .. " Xương");
			end
		end);
	end);
	local ToggleBone = Tabs.Main:AddToggle("ToggleBone", {Title="Cày Xương",Description="",Default=false});
	ToggleBone:OnChanged(function(Value)
		_G.AutoBone = Value;
		if (Value == false) then
			wait();
			Tween(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame);
			wait();
		end
	end);
	Options.ToggleBone:SetValue(false);
	local BoneCFrame = CFrame.new(-9515.75, 174.8521728515625, 6079.40625);
	spawn(function()
		while wait() do
			if _G.AutoBone then
				pcall(function()
					local QuestTitle = game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text;
					if not string.find(QuestTitle, "Demonic Soul") then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("AbandonQuest");
					end
					if (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == false) then
						Tween(BoneCFrame);
						if ((BoneCFrame.Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 3) then
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StartQuest", "HauntedQuest2", 1);
						end
					elseif (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == true) then
						if (game:GetService("Workspace").Enemies:FindFirstChild("Reborn Skeleton") or game:GetService("Workspace").Enemies:FindFirstChild("Living Zombie") or game:GetService("Workspace").Enemies:FindFirstChild("Demonic Soul") or game:GetService("Workspace").Enemies:FindFirstChild("Posessed Mummy")) then
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if (v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and (v.Humanoid.Health > 0)) then
									if ((v.Name == "Reborn Skeleton") or (v.Name == "Living Zombie") or (v.Name == "Demonic Soul") or (v.Name == "Posessed Mummy")) then
										if string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Demonic Soul") then
											repeat
												wait(_G.Fast_Delay);
												AttackNoCoolDown();
												AutoHaki();
												bringmob = true;
												EquipTool(SelectWeapon);
												Tween(v.HumanoidRootPart.CFrame * Pos);
												v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
												v.HumanoidRootPart.Transparency = 1;
												v.Humanoid.JumpPower = 0;
												v.Humanoid.WalkSpeed = 0;
												v.HumanoidRootPart.CanCollide = false;
												FarmPos = v.HumanoidRootPart.CFrame;
												MonFarm = v.Name;
											until not _G.AutoBone or (v.Humanoid.Health <= 0) or not v.Parent or (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == false) 
										else
											game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("AbandonQuest");
											bringmob = false;
										end
									end
								end
							end
						else
						end
					end
				end);
			end
		end
	end);
	local BoneNoQuest = CFrame.new(-9515.75, 174.8521728515625, 6079.40625);
	spawn(function()
		while wait() do
			if _G.AutoBoneNoQuest then
				pcall(function()
					Tween(BoneNoQuest);
					if ((BoneNoQuest.Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 3) then
					end
					if (game:GetService("Workspace").Enemies:FindFirstChild("Reborn Skeleton") or game:GetService("Workspace").Enemies:FindFirstChild("Living Zombie") or game:GetService("Workspace").Enemies:FindFirstChild("Demonic Soul") or game:GetService("Workspace").Enemies:FindFirstChild("Posessed Mummy")) then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and (v.Humanoid.Health > 0)) then
								if ((v.Name == "Reborn Skeleton") or (v.Name == "Living Zombie") or (v.Name == "Demonic Soul") or (v.Name == "Posessed Mummy")) then
									repeat
										wait(_G.Fast_Delay);
										AttackNoCoolDown();
										AutoHaki();
										bringmob = true;
										EquipTool(SelectWeapon);
										Tween(v.HumanoidRootPart.CFrame * Pos);
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										v.HumanoidRootPart.Transparency = 1;
										v.Humanoid.JumpPower = 0;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.CanCollide = false;
										FarmPos = v.HumanoidRootPart.CFrame;
										MonFarm = v.Name;
									until not _G.AutoBoneNoQuest or (v.Humanoid.Health <= 0) or not v.Parent 
								end
							end
						end
					end
				end);
			end
		end
	end);
	Tabs.Main:AddButton({Title="Cầu Nguyện",Description="",Callback=function()
		local args = {[1]="gravestoneEvent",[2]=1};
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
	end});
	Tabs.Main:AddButton({Title="Thử Vận May",Description="",Callback=function()
		local args = {[1]="gravestoneEvent",[2]=2};
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
	end});
	local ToggleRandomBone = Tabs.Main:AddToggle("ToggleRandomBone", {Title="Random Xương",Description="",Default=false});
	ToggleRandomBone:OnChanged(function(Value)
		_G.AutoRandomBone = Value;
	end);
	Options.ToggleRandomBone:SetValue(false);
	spawn(function()
		while wait() do
			if _G.AutoRandomBone then
				local args = {[1]="Bones",[2]="Buy",[3]=1,[4]=1};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
			end
		end
	end);
end
if Sea3 then
	local MiscFarm = Tabs.Main:AddSection("Tư Lệnh Bánh");
	local Mob_Kill_Cake_Prince = Tabs.Main:AddParagraph({Title="Trạng Thái Nó Ra",Content=""});
	spawn(function()
		while wait() do
			pcall(function()
				if (string.len(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CakePrinceSpawner")) == 88) then
					Mob_Kill_Cake_Prince:SetDesc("Còn: " .. string.sub(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CakePrinceSpawner"), 39, 41) .. "");
				elseif (string.len(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CakePrinceSpawner")) == 87) then
					Mob_Kill_Cake_Prince:SetDesc("Còn: " .. string.sub(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CakePrinceSpawner"), 39, 40) .. "");
				elseif (string.len(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CakePrinceSpawner")) == 86) then
					Mob_Kill_Cake_Prince:SetDesc("Còn: " .. string.sub(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CakePrinceSpawner"), 39, 39) .. " ");
				else
					Mob_Kill_Cake_Prince:SetDesc("Tư Lệnh Bánh : ✅️");
				end
			end);
		end
	end);
	local ToggleCake = Tabs.Main:AddToggle("ToggleCake", {Title="Cày Tư Lệnh Bánh",Description="",Default=false});
	local isFirstToggle = true;
	ToggleCake:OnChanged(function(Value)
		_G.CakePrince = Value;
		if Value then
			if isFirstToggle then
				isFirstToggle = false;
				local CakePos = CFrame.new(-2003.932861328125, 380.4824523925781, -12561.0185546875);
				Tween(CakePos);
			end
		else
			isFirstToggle = true;
			wait();
			Tween(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame);
			wait();
		end
	end);
	Options.ToggleCake:SetValue(false);
	spawn(function()
		while wait() do
			if _G.CakePrince then
				pcall(function()
					if game:GetService("Workspace").Enemies:FindFirstChild("Cake Prince") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Cake Prince") then
								if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
									repeat
										task.wait(_G.Fast_Delay);
										AutoHaki();
										EquipTool(SelectWeapon);
										v.HumanoidRootPart.CanCollide = false;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										Tween(v.HumanoidRootPart.CFrame * Pos);
										AttackNoCoolDown();
									until not _G.CakePrince or not v.Parent or (v.Humanoid.Health <= 0) 
								end
							end
						end
					elseif game:GetService("ReplicatedStorage"):FindFirstChild("Cake Prince [Lv. 2300] [Raid Boss]") then
						Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Cake Prince [Lv. 2300] [Raid Boss]").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
					elseif (game:GetService("Workspace").Map.CakeLoaf.BigMirror.Other.Transparency == 1) then
						if (game:GetService("Workspace").Enemies:FindFirstChild("Cookie Crafter") or game:GetService("Workspace").Enemies:FindFirstChild("Cake Guard") or game:GetService("Workspace").Enemies:FindFirstChild("Baking Staff") or game:GetService("Workspace").Enemies:FindFirstChild("Head Baker")) then
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if ((v.Name == "Cookie Crafter") or (v.Name == "Cake Guard") or (v.Name == "Baking Staff") or (v.Name == "Head Baker")) then
									if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
										repeat
											task.wait(_G.Fast_Delay);
											AutoHaki();
											bringmob = true;
											EquipTool(SelectWeapon);
											v.HumanoidRootPart.CanCollide = false;
											v.Humanoid.WalkSpeed = 0;
											v.Head.CanCollide = false;
											v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
											FarmPos = v.HumanoidRootPart.CFrame;
											MonFarm = v.Name;
											Tween(v.HumanoidRootPart.CFrame * Pos);
											AttackNoCoolDown();
										until not _G.CakePrince or not v.Parent or (v.Humanoid.Health <= 0) or (game:GetService("Workspace").Map.CakeLoaf.BigMirror.Other.Transparency == 0) or game:GetService("ReplicatedStorage"):FindFirstChild("Cake Prince [Lv. 2300] [Raid Boss]") or game:GetService("Workspace").Enemies:FindFirstChild("Cake Prince [Lv. 2300] [Raid Boss]") 
										bringmob = false;
									end
								end
							end
						end
					end
				end);
			end
		end
	end);
	local ToggleDoughKing = Tabs.Main:AddToggle("ToggleDoughKing", {Title="Đấm Vua Bột",Description="",Default=false});
	ToggleDoughKing:OnChanged(function(Value)
		_G.DoughKing = Value;
		if (Value == false) then
			wait();
			Tween(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame);
			wait();
		end
	end);
	Options.ToggleDoughKing:SetValue(false);
	spawn(function()
		while wait() do
			if _G.DoughKing then
				pcall(function()
					if game:GetService("Workspace").Enemies:FindFirstChild("Dough King") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Dough King") then
								if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
									repeat
										task.wait(_G.Fast_Delay);
										AutoHaki();
										EquipTool(SelectWeapon);
										v.HumanoidRootPart.CanCollide = false;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										Tween(v.HumanoidRootPart.CFrame * Pos);
										AttackNoCoolDown();
									until not _G.DoughKing or not v.Parent or (v.Humanoid.Health <= 0) 
								end
							end
						end
					end
				end);
			end
		end
	end);
	local ToggleSpawnCake = Tabs.Main:AddToggle("ToggleSpawnCake", {Title="Triệu Hồi Tư Lệnh Bánh",Description="",Default=true});
	ToggleSpawnCake:OnChanged(function(Value)
		_G.SpawnCakePrince = Value;
	end);
	Options.ToggleSpawnCake:SetValue(true);
end
spawn(function()
	while wait() do
		if _G.SpawnCakePrince then
			local args = {[1]="CakePrinceSpawner",[2]=true};
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
			local args = {[1]="CakePrinceSpawner"};
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
		end
	end
end);
if Sea2 then
	local MiscFarm = Tabs.Main:AddSection("Ectoplasm Farm");
	local ToggleVatChatKiDi = Tabs.Main:AddToggle("ToggleVatChatKiDi", {Title="Auto Farm Ectoplasm",Description="",Default=false});
	ToggleVatChatKiDi:OnChanged(function(Value)
		_G.Ectoplasm = Value;
	end);
	Options.ToggleVatChatKiDi:SetValue(false);
	spawn(function()
		while wait() do
			pcall(function()
				if _G.Ectoplasm then
					if (game:GetService("Workspace").Enemies:FindFirstChild("Ship Deckhand") or game:GetService("Workspace").Enemies:FindFirstChild("Ship Engineer") or game:GetService("Workspace").Enemies:FindFirstChild("Ship Steward") or game:GetService("Workspace").Enemies:FindFirstChild("Ship Officer")) then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if ((v.Name == "Ship Steward") or (v.Name == "Ship Engineer") or (v.Name == "Ship Deckhand") or ((v.Name == "Ship Officer") and v:FindFirstChild("Humanoid"))) then
								if (v.Humanoid.Health > 0) then
									repeat
										wait(_G.Fast_Delay);
										AttackNoCoolDown();
										AutoHaki();
										bringmob = true;
										EquipTool(SelectWeapon);
										Tween(v.HumanoidRootPart.CFrame * Pos);
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										v.HumanoidRootPart.Transparency = 1;
										v.Humanoid.JumpPower = 0;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.CanCollide = false;
										FarmPos = v.HumanoidRootPart.CFrame;
										MonFarm = v.Name;
									until (_G.Ectoplasm == false) or not v.Parent or (v.Humanoid.Health == 0) or not game:GetService("Workspace").Enemies:FindFirstChild(v.Name) 
									bringmob = false;
								end
							end
						end
					else
						local Distance = (Vector3.new(904.4072265625, 181.05767822266, 33341.38671875) - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude;
						if (Distance > 20000) then
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(923.21252441406, 126.9760055542, 32852.83203125));
						end
						Tween(CFrame.new(904.4072265625, 181.05767822266, 33341.38671875));
					end
				end
			end);
		end
	end);
end
local boss = Tabs.Main:AddSection("Trùm");
if Sea1 then
	tableBoss = {"The Gorilla King","Bobby","Yeti","Mob Leader","Vice Admiral","Warden","Chief Warden","Swan","Magma Admiral","Fishman Lord","Wysper","Thunder God","Cyborg","Saber Expert"};
elseif Sea2 then
	tableBoss = {"Diamond","Jeremy","Fajita","Don Swan","Smoke Admiral","Cursed Captain","Darkbeard","Order","Awakened Ice Admiral","Tide Keeper"};
elseif Sea3 then
	tableBoss = {"Stone","Hydra Leader","Kilo Admiral","Captain Elephant","Beautiful Pirate","rip_indra True Form","Longma","Soul Reaper","Cake Queen"};
end
local DropdownBoss = Tabs.Main:AddDropdown("DropdownBoss", {Title="Chọn Trùm",Description="",Values=tableBoss,Multi=false,Default=1});
DropdownBoss:SetValue(_G.SelectBoss);
DropdownBoss:OnChanged(function(Value)
	_G.SelectBoss = Value;
end);
local ToggleAutoFarmBoss = Tabs.Main:AddToggle("ToggleAutoFarmBoss", {Title="Đấm Trùm",Description="",Default=false});
ToggleAutoFarmBoss:OnChanged(function(Value)
	_G.AutoBoss = Value;
end);
Options.ToggleAutoFarmBoss:SetValue(false);
spawn(function()
	while wait() do
		if _G.AutoBoss then
			pcall(function()
				if game:GetService("Workspace").Enemies:FindFirstChild(_G.SelectBoss) then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (v.Name == _G.SelectBoss) then
							if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
								repeat
									wait(_G.Fast_Delay);
									AttackNoCoolDown();
									AutoHaki();
									EquipTool(SelectWeapon);
									v.HumanoidRootPart.CanCollide = false;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									sethiddenproperty(game:GetService("Players").LocalPlayer, "SimulationRadius", math.huge);
								until not _G.AutoBoss or not v.Parent or (v.Humanoid.Health <= 0) 
							end
						end
					end
				elseif game:GetService("ReplicatedStorage"):FindFirstChild(_G.SelectBoss) then
					Tween(game:GetService("ReplicatedStorage"):FindFirstChild(_G.SelectBoss).HumanoidRootPart.CFrame * CFrame.new(5, 10, 7));
				end
			end);
		end
	end
end);
local Material = Tabs.Main:AddSection("Nguyên Liệu");
if Sea1 then
	MaterialList = {"Scrap Metal","Leather","Angel Wings","Magma Ore","Fish Tail"};
elseif Sea2 then
	MaterialList = {"Scrap Metal","Leather","Radioactive Material","Mystic Droplet","Magma Ore","Vampire Fang"};
elseif Sea3 then
	MaterialList = {"Scrap Metal","Leather","Demonic Wisp","Conjured Cocoa","Dragon Scale","Gunpowder","Fish Tail","Mini Tusk","Hydra Enforcer","Venomous Assailant"};
end
local DropdownMaterial = Tabs.Main:AddDropdown("DropdownMaterial", {Title="Chọn Nguyên Liệu",Description="",Values=MaterialList,Multi=false,Default=1});
DropdownMaterial:SetValue(SelectMaterial);
DropdownMaterial:OnChanged(function(Value)
	SelectMaterial = Value;
end);
local ToggleMaterial = Tabs.Main:AddToggle("ToggleMaterial", {Title="Cày Nguyên Liệu",Description="",Default=false});
ToggleMaterial:OnChanged(function(Value)
	_G.AutoMaterial = Value;
	if (Value == false) then
		wait();
		Tween(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame);
		wait();
	end
end);
Options.ToggleMaterial:SetValue(false);
spawn(function()
	while task.wait() do
		if _G.AutoMaterial then
			pcall(function()
				MaterialMon(SelectMaterial);
				Tween(MPos);
				if game:GetService("Workspace").Enemies:FindFirstChild(MMon) then
					for i, v in pairs(game.Workspace.Enemies:GetChildren()) do
						if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
							if (v.Name == MMon) then
								repeat
									wait(_G.Fast_Delay);
									AttackNoCoolDown();
									AutoHaki();
									bringmob = true;
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
									v.HumanoidRootPart.Transparency = 1;
									v.Humanoid.JumpPower = 0;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.CanCollide = false;
									FarmPos = v.HumanoidRootPart.CFrame;
									MonFarm = v.Name;
								until not _G.AutoMaterial or not v.Parent or (v.Humanoid.Health <= 0) 
								bringmob = false;
							end
						end
					end
				else
					for i, v in pairs(game:GetService("Workspace")['_WorldOrigin'].EnemySpawns:GetChildren()) do
						if string.find(v.Name, Mon) then
							if ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - v.Position).Magnitude >= 10) then
								Tween(v.HumanoidRootPart.CFrame * Pos);
							end
						end
					end
				end
			end);
		end
	end
end);
if Sea3 then
	local RoughSea = Tabs.Sea:AddSection("Đảo Cáo");
	local StatusKitsune = Tabs.Sea:AddParagraph({Title="Trạng Thái Đảo Cáo",Content=""});
	function UpdateKitsune()
		if game:GetService("Workspace").Map:FindFirstChild("KitsuneIsland") then
			StatusKitsune:SetDesc("Đảo Cáo : ✅️");
		else
			StatusKitsune:SetDesc("Đảo Cáo : ❌️");
		end
	end
	spawn(function()
		pcall(function()
			while wait() do
				UpdateKitsune();
			end
		end);
	end);
	local ToggleEspKitsune = Tabs.Sea:AddToggle("ToggleEspKitsune", {Title="Định Vị Đảo Cáo",Description="",Default=false});
	ToggleEspKitsune:OnChanged(function(Value)
		KitsuneIslandEsp = Value;
		while KitsuneIslandEsp do
			wait();
			UpdateIslandKisuneESP();
		end
	end);
	Options.ToggleEspKitsune:SetValue(false);
	function UpdateIslandKisuneESP()
		for i, v in pairs(game:GetService("Workspace")['_WorldOrigin'].Locations:GetChildren()) do
			pcall(function()
				if KitsuneIslandEsp then
					if (v.Name == "Kitsune Island") then
						if not v:FindFirstChild("NameEsp") then
							local bill = Instance.new("BillboardGui", v);
							bill.Name = "NameEsp";
							bill.ExtentsOffset = Vector3.new(0, 1, 0);
							bill.Size = UDim2.new(1, 200, 1, 30);
							bill.Adornee = v;
							bill.AlwaysOnTop = true;
							local name = Instance.new("TextLabel", bill);
							name.Font = "Code";
							name.FontSize = "Size14";
							name.TextWrapped = true;
							name.Size = UDim2.new(1, 0, 1, 0);
							name.TextYAlignment = "Top";
							name.BackgroundTransparency = 1;
							name.TextStrokeTransparency = 0.5;
							name.TextColor3 = Color3.fromRGB(80, 245, 245);
						else
							v['NameEsp'].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " M";
						end
					end
				elseif v:FindFirstChild("NameEsp") then
					v:FindFirstChild("NameEsp"):Destroy();
				end
			end);
		end
	end
	local ToggleTPKitsune = Tabs.Sea:AddToggle("ToggleTPKitsune", {Title="Bay Vô Đảo Cáo",Description="",Default=false});
	ToggleTPKitsune:OnChanged(function(Value)
		_G.TweenToKitsune = Value;
	end);
	Options.ToggleTPKitsune:SetValue(false);
	spawn(function()
		local kitsuneIsland;
		while not kitsuneIsland do
			kitsuneIsland = game:GetService("Workspace").Map:FindFirstChild("KitsuneIsland");
			wait();
		end
		while wait() do
			if _G.TweenToKitsune then
				local shrineActive = kitsuneIsland:FindFirstChild("ShrineActive");
				if shrineActive then
					for _, v in pairs(shrineActive:GetDescendants()) do
						if (v:IsA("BasePart") and v.Name:find("NeonShrinePart")) then
							Tween(v.CFrame);
						end
					end
				end
			end
		end
	end);
	local ToggleCollectAzure = Tabs.Sea:AddToggle("ToggleCollectAzure", {Title="Lụm Linh Hồn Xanh",Description="",Default=false});
	ToggleCollectAzure:OnChanged(function(Value)
		_G.CollectAzure = Value;
	end);
	Options.ToggleCollectAzure:SetValue(false);
	spawn(function()
		while wait() do
			if _G.CollectAzure then
				pcall(function()
					if game:GetService("Workspace"):FindFirstChild("AttachedAzureEmber") then
						Tween(game:GetService("Workspace"):WaitForChild("EmberTemplate"):FindFirstChild("Part").CFrame);
					end
				end);
			end
		end
	end);
end
Tabs.Sea:AddButton({Title="Đổi Linh Hồn Xanh",Description="",Callback=function()
	game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Net"):WaitForChild("RF/KitsuneStatuePray"):InvokeServer();
end});
if Sea3 then
	local RoughSea = Tabs.Sea:AddSection("Biển");
	local Players = game:GetService("Players");
	local RunService = game:GetService("RunService");
	local VirtualInputManager = game:GetService("VirtualInputManager");
	local Workspace = game:GetService("Workspace");
	local SetSpeedBoat = 350;
	local SetSpeedBoatSlider = Tabs.Sea:AddSlider("SliderSpeedBoat", {Title="Tốc Độ Thuyền",Description="",Default=SetSpeedBoat,Min=0,Max=350,Rounding=1,Callback=function(value)
		SetSpeedBoat = value;
	end});
	SetSpeedBoatSlider:SetValue(SetSpeedBoat);
	local AutoFindPrehistoricToggle = Tabs.Sea:AddToggle("AutoFindPrehistoric", {Title="Tìm Đảo Dung Nham",Description="",Default=false});
	Options.AutoFindPrehistoric:SetValue(false);
	AutoFindPrehistoricToggle:OnChanged(function(value)
		_G.AutoFindPrehistoric = value;
	end);
	local seatHistory = {};
	local isTeleporting = false;
	local notified = false;
	RunService.RenderStepped:Connect(function()
		if not _G.AutoFindPrehistoric then
			notified = false;
			return;
		end
		local player = Players.LocalPlayer;
		local character = player.Character;
		if (not character or not character:FindFirstChild("Humanoid")) then
			return;
		end
		local function tpToMyBoat()
			if isTeleporting then
				return;
			end
			isTeleporting = true;
			for boatName, seat in pairs(seatHistory) do
				if (seat and seat.Parent and (seat.Name == "VehicleSeat") and not seat.Occupant) then
					Tween2(seat.CFrame);
					break;
				end
			end
			isTeleporting = false;
		end
		local humanoid = character.Humanoid;
		local boatFound = false;
		local currentBoat = nil;
		for _, b in pairs(Workspace.Boats:GetChildren()) do
			local seat = b:FindFirstChild("VehicleSeat");
			if (seat and (seat.Occupant == humanoid)) then
				boatFound = true;
				currentBoat = seat;
				seatHistory[b.Name] = seat;
			elseif (seat and (seat.Occupant == nil)) then
				tpToMyBoat();
			end
		end
		if not boatFound then
			return;
		end
		currentBoat.MaxSpeed = SetSpeedBoat;
		currentBoat.CFrame = CFrame.new(Vector3.new(currentBoat.Position.X, currentBoat.Position.Y, currentBoat.Position.Z)) * currentBoat.CFrame.Rotation;
		VirtualInputManager:SendKeyEvent(true, "W", false, game);
		for _, v in pairs(Workspace.Boats:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false;
			end
		end
		for _, v in pairs(character:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false;
			end
		end
		local islandsToDelete = {"ShipwreckIsland","SandIsland","TreeIsland","TinyIsland","MysticIsland","KitsuneIsland","FrozenDimension"};
		for _, islandName in ipairs(islandsToDelete) do
			local island = Workspace.Map:FindFirstChild(islandName);
			if (island and island:IsA("Model")) then
				island:Destroy();
			end
		end
		local prehistoricIsland = Workspace.Map:FindFirstChild("PrehistoricIsland");
		if prehistoricIsland then
			VirtualInputManager:SendKeyEvent(false, "W", false, game);
			_G.AutoFindPrehistoric = false;
			if not notified then
				Fluent:Notify({Title="Ldt Hub",Content="Đảo Dung Nham Tìm Thấy",Duration=10});
				notified = true;
			end
			return;
		end
	end);
	local AutoFindMirageToggle = Tabs.Sea:AddToggle("AutoFindMirage", {Title="Tìm Đảo Bí Ẩn",Description="",Default=false});
	Options.AutoFindMirage:SetValue(false);
	AutoFindMirageToggle:OnChanged(function(value)
		_G.AutoFindMirage = value;
	end);
	local seatHistory = {};
	local isTeleporting = false;
	local notified = false;
	RunService.RenderStepped:Connect(function()
		if not _G.AutoFindMirage then
			notified = false;
			return;
		end
		local player = Players.LocalPlayer;
		local character = player.Character;
		if (not character or not character:FindFirstChild("Humanoid")) then
			return;
		end
		local function tpToMyBoat()
			if isTeleporting then
				return;
			end
			isTeleporting = true;
			for boatName, seat in pairs(seatHistory) do
				if (seat and seat.Parent and (seat.Name == "VehicleSeat") and not seat.Occupant) then
					Tween2(seat.CFrame);
					break;
				end
			end
			isTeleporting = false;
		end
		local humanoid = character.Humanoid;
		local boatFound = false;
		local currentBoat = nil;
		for _, b in pairs(Workspace.Boats:GetChildren()) do
			local seat = b:FindFirstChild("VehicleSeat");
			if (seat and (seat.Occupant == humanoid)) then
				boatFound = true;
				currentBoat = seat;
				seatHistory[b.Name] = seat;
			elseif (seat and (seat.Occupant == nil)) then
				tpToMyBoat();
			end
		end
		if not boatFound then
			return;
		end
		currentBoat.MaxSpeed = SetSpeedBoat;
		currentBoat.CFrame = CFrame.new(Vector3.new(currentBoat.Position.X, currentBoat.Position.Y, currentBoat.Position.Z)) * currentBoat.CFrame.Rotation;
		VirtualInputManager:SendKeyEvent(true, "W", false, game);
		for _, v in pairs(Workspace.Boats:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false;
			end
		end
		for _, v in pairs(character:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false;
			end
		end
		local islandsToDelete = {"ShipwreckIsland","SandIsland","TreeIsland","TinyIsland","PrehistoricIsland","KitsuneIsland","FrozenDimension"};
		for _, islandName in ipairs(islandsToDelete) do
			local island = Workspace.Map:FindFirstChild(islandName);
			if (island and island:IsA("Model")) then
				island:Destroy();
			end
		end
		local mirageIsland = Workspace.Map:FindFirstChild("MysticIsland");
		if mirageIsland then
			VirtualInputManager:SendKeyEvent(false, "W", false, game);
			_G.AutoFindMirage = false;
			if not notified then
				Fluent:Notify({Title="Ldt Hub",Content="Đảo Bí Ẩn Tìm Thấy",Duration=10});
				notified = true;
			end
			return;
		end
	end);
	local AutoFindFrozenToggle = Tabs.Sea:AddToggle("AutoFindFrozen", {Title="Tìm Đảo Leviathan",Description="Cần 5 Người Không Idk",Default=false});
	Options.AutoFindFrozen:SetValue(false);
	AutoFindFrozenToggle:OnChanged(function(value)
		_G.AutoFindFrozen = value;
	end);
	local seatHistory = {};
	local isTeleporting = false;
	local notified = false;
	RunService.RenderStepped:Connect(function()
		if not _G.AutoFindFrozen then
			notified = false;
			return;
		end
		local player = Players.LocalPlayer;
		local character = player.Character;
		if (not character or not character:FindFirstChild("Humanoid")) then
			return;
		end
		local function tpToMyBoat()
			if isTeleporting then
				return;
			end
			isTeleporting = true;
			for boatName, seat in pairs(seatHistory) do
				if (seat and seat.Parent and (seat.Name == "VehicleSeat") and not seat.Occupant) then
					Tween2(seat.CFrame);
					break;
				end
			end
			isTeleporting = false;
		end
		local humanoid = character.Humanoid;
		local boatFound = false;
		local currentBoat = nil;
		for _, b in pairs(Workspace.Boats:GetChildren()) do
			local seat = b:FindFirstChild("VehicleSeat");
			if (seat and (seat.Occupant == humanoid)) then
				boatFound = true;
				currentBoat = seat;
				seatHistory[b.Name] = seat;
			elseif (seat and (seat.Occupant == nil)) then
				tpToMyBoat();
			end
		end
		if not boatFound then
			return;
		end
		currentBoat.MaxSpeed = SetSpeedBoat;
		currentBoat.CFrame = CFrame.new(Vector3.new(currentBoat.Position.X, currentBoat.Position.Y, currentBoat.Position.Z)) * currentBoat.CFrame.Rotation;
		VirtualInputManager:SendKeyEvent(true, "W", false, game);
		for _, v in pairs(Workspace.Boats:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false;
			end
		end
		for _, v in pairs(character:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false;
			end
		end
		local islandsToDelete = {"ShipwreckIsland","SandIsland","TreeIsland","TinyIsland","MysticIsland","KitsuneIsland","PrehistoricIsland"};
		for _, islandName in ipairs(islandsToDelete) do
			local island = Workspace.Map:FindFirstChild(islandName);
			if (island and island:IsA("Model")) then
				island:Destroy();
			end
		end
		local frozenDimension = Workspace.Map:FindFirstChild("FrozenDimension");
		if frozenDimension then
			VirtualInputManager:SendKeyEvent(false, "W", false, game);
			_G.AutoFindFrozen = false;
			if not notified then
				Fluent:Notify({Title="Ldt Hub",Content="Đảo Leviathan Tìm Thấy",Duration=10});
				notified = true;
			end
			return;
		end
	end);
	local AutoComeTikiToggle = Tabs.Sea:AddToggle("AutoComeTiki", {Title="Lái Thuyền Về Đảo Tiki",Description="",Default=false});
	AutoComeTikiToggle:OnChanged(function(value)
		_G.AutoComeTiki = value;
	end);
	RunService.RenderStepped:Connect(function()
		if not _G.AutoComeTiki then
			return;
		end
		local player = Players.LocalPlayer;
		local character = player.Character;
		if (not character or not character:FindFirstChild("Humanoid")) then
			return;
		end
		local humanoid = character.Humanoid;
		local boat = nil;
		for _, b in pairs(Workspace.Boats:GetChildren()) do
			local seat = b:FindFirstChild("VehicleSeat");
			if (seat and (seat.Occupant == humanoid)) then
				boat = seat;
				break;
			end
		end
		if boat then
			boat.MaxSpeed = SetSpeedBoat;
			local tikiPosition = CFrame.new(-16217.7568359375, 9.126761436462402, 446.06536865234375);
			local currentPosition = boat.Position;
			local targetPosition = tikiPosition.Position;
			local direction = (targetPosition - currentPosition).unit;
			local moveVector = direction * boat.MaxSpeed * RunService.RenderStepped:Wait();
			boat.CFrame = boat.CFrame + moveVector;
			local lookAt = CFrame.new(currentPosition, targetPosition);
			boat.CFrame = CFrame.new(boat.Position, targetPosition);
			if ((boat.Position - targetPosition).magnitude < 120) then
				_G.AutoComeTiki = false;
				VirtualInputManager:SendKeyEvent(false, "W", false, game);
			end
		end
	end);
	local AutoComeHydraToggle = Tabs.Sea:AddToggle("AutoComeHydra", {Title="Lái Thuyền Về Đảo Hydra",Description="",Default=false});
	AutoComeHydraToggle:OnChanged(function(value)
		_G.AutoComeHydra = value;
	end);
	RunService.RenderStepped:Connect(function()
		if not _G.AutoComeHydra then
			return;
		end
		local player = Players.LocalPlayer;
		local character = player.Character;
		if (not character or not character:FindFirstChild("Humanoid")) then
			return;
		end
		local humanoid = character.Humanoid;
		local boat = nil;
		for _, b in pairs(Workspace.Boats:GetChildren()) do
			local seat = b:FindFirstChild("VehicleSeat");
			if (seat and (seat.Occupant == humanoid)) then
				boat = seat;
				break;
			end
		end
		if boat then
			boat.MaxSpeed = SetSpeedBoat;
			local tikiPosition = CFrame.new(5193.9375, -0.04690289497375488, 1631.578369140625);
			local currentPosition = boat.Position;
			local targetPosition = tikiPosition.Position;
			local direction = (targetPosition - currentPosition).unit;
			local moveVector = direction * boat.MaxSpeed * RunService.RenderStepped:Wait();
			boat.CFrame = boat.CFrame + moveVector;
			local lookAt = CFrame.new(currentPosition, targetPosition);
			boat.CFrame = CFrame.new(boat.Position, targetPosition);
			if ((boat.Position - targetPosition).magnitude < 120) then
				_G.AutoComeHydra = false;
				VirtualInputManager:SendKeyEvent(false, "W", false, game);
			end
		end
	end);
	Tabs.Sea:AddButton({Title="Bay Đến Khu Vực Săn",Description="",Callback=function()
		Tween2(CFrame.new(-16917.154296875, 7.757596015930176, 511.8203125));
	end});
	local seatHistory = {};
	local boatList = {"Beast Hunter","Sleigh","Miracle","The Sentinel","Guardian","Lantern","Dinghy","PirateSloop","PirateBrigade","PirateGrandBrigade","MarineGrandBrigade","MarineBrigade","MarineSloop"};
	local DropdownBoat = Tabs.Sea:AddDropdown("DropdownBoat", {Title="Chọn Thuyền",Description="",Values=boatList,Multi=false,Default=1});
	DropdownBoat:SetValue(selectedBoat);
	DropdownBoat:OnChanged(function(Value)
		selectedBoat = Value;
	end);
	local function buyBoat(boatName)
		local args = {[1]="BuyBoat",[2]=boatName};
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
		task.delay(2, function()
			for _, boat in pairs(Workspace.Boats:GetChildren()) do
				if (boat:IsA("Model") and (boat.Name == boatName)) then
					local seat = boat:FindFirstChild("VehicleSeat");
					if (seat and not seat.Occupant) then
						seatHistory[boatName] = seat;
					end
				end
			end
		end);
	end
	local function tpToMyBoat()
		for boatName, seat in pairs(seatHistory) do
			if (seat and seat.Parent and (seat.Name == "VehicleSeat") and not seat.Occupant) then
				Tween2(seat.CFrame);
			end
		end
	end
	game:GetService("RunService").RenderStepped:Connect(function()
		for boatName, seat in pairs(seatHistory) do
			if (seat and seat.Parent and (seat.Name == "VehicleSeat") and not seat.Occupant) then
				seatHistory[boatName] = seat;
			end
		end
	end);
	Tabs.Sea:AddButton({Title="Mua Thuyền",Description="",Callback=function()
		buyBoat(selectedBoat);
	end});
	Tabs.Sea:AddButton({Title="Bay Đến Thuyền",Description="Duy Nhất Thuyền Bạn Mua Ở Chỗ Chọn",Callback=function()
		tpToMyBoat();
	end});
	local ToggleTerrorshark = Tabs.Sea:AddToggle("ToggleTerrorshark", {Title="Đấm Cá Mập",Description="",Default=false});
	ToggleTerrorshark:OnChanged(function(Value)
		_G.AutoTerrorshark = Value;
	end);
	Options.ToggleTerrorshark:SetValue(false);
	spawn(function()
		while wait() do
			if _G.AutoTerrorshark then
				pcall(function()
					if game:GetService("Workspace").Enemies:FindFirstChild("Terrorshark") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Terrorshark") then
								if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
									repeat
										wait(_G.Fast_Delay);
										AttackNoCoolDown();
										AutoHaki();
										EquipTool(SelectWeapon);
										v.HumanoidRootPart.CanCollide = false;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										Tween(v.HumanoidRootPart.CFrame * Pos);
									until not _G.AutoTerrorshark or not v.Parent or (v.Humanoid.Health <= 0) 
								end
							end
						end
					elseif game:GetService("ReplicatedStorage"):FindFirstChild("Terrorshark") then
						Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Terrorshark").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
					else
					end
				end);
			end
		end
	end);
	local TogglePiranha = Tabs.Sea:AddToggle("TogglePiranha", {Title="Đấm Piranha",Description="",Default=false});
	TogglePiranha:OnChanged(function(Value)
		_G.farmpiranya = Value;
	end);
	Options.TogglePiranha:SetValue(false);
	spawn(function()
		while wait() do
			if _G.farmpiranya then
				pcall(function()
					if game:GetService("Workspace").Enemies:FindFirstChild("Piranha") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Piranha") then
								if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
									repeat
										wait(_G.Fast_Delay);
										AttackNoCoolDown();
										AutoHaki();
										EquipTool(SelectWeapon);
										v.HumanoidRootPart.CanCollide = false;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										Tween(v.HumanoidRootPart.CFrame * Pos);
									until not _G.farmpiranya or not v.Parent or (v.Humanoid.Health <= 0) 
								end
							end
						end
					elseif game:GetService("ReplicatedStorage"):FindFirstChild("Piranha") then
						Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Piranha").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
					else
					end
				end);
			end
		end
	end);
	local ToggleShark = Tabs.Sea:AddToggle("ToggleShark", {Title="Đấm Cá Con",Description="",Default=false});
	ToggleShark:OnChanged(function(Value)
		_G.AutoShark = Value;
	end);
	Options.ToggleShark:SetValue(false);
	spawn(function()
		while wait() do
			if _G.AutoShark then
				pcall(function()
					if game:GetService("Workspace").Enemies:FindFirstChild("Shark") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Shark") then
								if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
									repeat
										wait(_G.Fast_Delay);
										AttackNoCoolDown();
										AutoHaki();
										EquipTool(SelectWeapon);
										v.HumanoidRootPart.CanCollide = false;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										Tween(v.HumanoidRootPart.CFrame * Pos);
										game.Players.LocalPlayer.Character.Humanoid.Sit = false;
									until not _G.AutoShark or not v.Parent or (v.Humanoid.Health <= 0) 
								end
							end
						end
					else
						Tween(game:GetService("Workspace").Boats.PirateGrandBrigade.VehicleSeat.CFrame * CFrame.new(0, 1, 0));
						if game:GetService("ReplicatedStorage"):FindFirstChild("Terrorshark") then
							Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Terrorshark").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
						else
						end
					end
				end);
			end
		end
	end);
	local ToggleFishCrew = Tabs.Sea:AddToggle("ToggleFishCrew", {Title="Đấm Tàu Cá",Description="",Default=false});
	ToggleFishCrew:OnChanged(function(Value)
		_G.AutoFishCrew = Value;
	end);
	Options.ToggleFishCrew:SetValue(false);
	spawn(function()
		while wait() do
			if _G.AutoFishCrew then
				pcall(function()
					if game:GetService("Workspace").Enemies:FindFirstChild("Fish Crew Member") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Fish Crew Member") then
								if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
									repeat
										wait(_G.Fast_Delay);
										AttackNoCoolDown();
										AutoHaki();
										EquipTool(SelectWeapon);
										v.HumanoidRootPart.CanCollide = false;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										Tween(v.HumanoidRootPart.CFrame * Pos);
										game.Players.LocalPlayer.Character.Humanoid.Sit = false;
									until not _G.AutoFishCrew or not v.Parent or (v.Humanoid.Health <= 0) 
								end
							end
						end
					else
						Tween(game:GetService("Workspace").Boats.PirateGrandBrigade.VehicleSeat.CFrame * CFrame.new(0, 1, 0));
						if game:GetService("ReplicatedStorage"):FindFirstChild("Fish Crew Member") then
							Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Fish Crew Member").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
						else
						end
					end
				end);
			end
		end
	end);
	local ToggleShip = Tabs.Sea:AddToggle("ToggleShip", {Title="Đấm Tàu",Description="",Default=false});
	ToggleShip:OnChanged(function(Value)
		_G.Ship = Value;
	end);
	Options.ToggleShip:SetValue(false);
	function CheckPirateBoat()
		local checkmmpb = {"PirateGrandBrigade","PirateBrigade"};
		for r, v in next, game:GetService("Workspace").Enemies:GetChildren() do
			if (table.find(checkmmpb, v.Name) and v:FindFirstChild("Health") and (v.Health.Value > 0)) then
				return v;
			end
		end
	end
	spawn(function()
		while wait() do
			if _G.Ship then
				pcall(function()
					if CheckPirateBoat() then
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 32, false, game);
						wait(0.5);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 32, false, game);
						local v = CheckPirateBoat();
						repeat
							wait();
							spawn(Tween(v.Engine.CFrame * CFrame.new(0, -20, 0)), 1);
							AimBotSkillPosition = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(0, -5, 0);
							Skillaimbot = true;
							AutoSkill = false;
						until not v or not v.Parent or (v.Health.Value <= 0) or not CheckPirateBoat() 
						Skillaimbot = true;
						AutoSkill = false;
					end
				end);
			end
		end
	end);
	local ToggleGhostShip = Tabs.Sea:AddToggle("ToggleGhostShip", {Title="Đấm Tàu Ma",Description="",Default=false});
	ToggleGhostShip:OnChanged(function(Value)
		_G.GhostShip = Value;
	end);
	Options.ToggleGhostShip:SetValue(false);
	function CheckPirateBoat()
		local checkmmpb = {"FishBoat"};
		for r, v in next, game:GetService("Workspace").Enemies:GetChildren() do
			if (table.find(checkmmpb, v.Name) and v:FindFirstChild("Health") and (v.Health.Value > 0)) then
				return v;
			end
		end
	end
	spawn(function()
		while wait() do
			pcall(function()
				if _G.bjirFishBoat then
					if CheckPirateBoat() then
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 32, false, game);
						wait();
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 32, false, game);
						local v = CheckPirateBoat();
						repeat
							wait();
							spawn(Tween(v.Engine.CFrame * CFrame.new(0, -20, 0), 1));
							AutoSkill = true;
							Skillaimbot = true;
							AimBotSkillPosition = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(0, -5, 0);
						until v.Parent or (v.Health.Value <= 0) or not CheckPirateBoat() 
						AutoSkill = false;
						Skillaimbot = false;
					end
				end
			end);
		end
	end);
	spawn(function()
		while wait() do
			if _G.bjirFishBoat then
				pcall(function()
					if CheckPirateBoat() then
						AutoHaki();
						game:GetService("VirtualUser"):CaptureController();
						game:GetService("VirtualUser"):Button1Down(Vector2.new(1280, 672));
						for i, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
							if v:IsA("Tool") then
								if (v.ToolTip == "Melee") then
									game.Players.LocalPlayer.Character.Humanoid:EquipTool(v);
								end
							end
						end
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, "C", false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						for i, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
							if v:IsA("Tool") then
								if (v.ToolTip == "Blox Fruit") then
									game.Players.LocalPlayer.Character.Humanoid:EquipTool(v);
								end
							end
						end
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, "V", false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, "V", false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait();
						for i, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
							if v:IsA("Tool") then
								if (v.ToolTip == "Sword") then
									game.Players.LocalPlayer.Character.Humanoid:EquipTool(v);
								end
							end
						end
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait();
						for i, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
							if v:IsA("Tool") then
								if (v.ToolTip == "Gun") then
									game.Players.LocalPlayer.Character.Humanoid:EquipTool(v);
								end
							end
						end
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						wait(0.2);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
					end
				end);
			end
		end
	end);
	local AutoElite = Tabs.Main:AddSection("Elite");
	local StatusElite = Tabs.Main:AddParagraph({Title="Trạng Thái Elite",Content=""});
	spawn(function()
		while wait() do
			pcall(function()
				if (game:GetService("ReplicatedStorage"):FindFirstChild("Diablo") or game:GetService("ReplicatedStorage"):FindFirstChild("Deandre") or game:GetService("ReplicatedStorage"):FindFirstChild("Urban") or game:GetService("Workspace").Enemies:FindFirstChild("Diablo") or game:GetService("Workspace").Enemies:FindFirstChild("Deandre") or game:GetService("Workspace").Enemies:FindFirstChild("Urban")) then
					StatusElite:SetDesc("Elite Boss: ✅️ | Killed: " .. game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("EliteHunter", "Progress"));
				else
					StatusElite:SetDesc("Elite Boss: ❌️ | Killed: " .. game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("EliteHunter", "Progress"));
				end
			end);
		end
	end);
	local ToggleElite = Tabs.Main:AddToggle("ToggleElite", {Title="Đấm Elite",Description="",Default=false});
	ToggleElite:OnChanged(function(Value)
		_G.AutoElite = Value;
	end);
	Options.ToggleElite:SetValue(false);
	spawn(function()
		while task.wait() do
			if _G.AutoElite then
				pcall(function()
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("EliteHunter");
					if (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == true) then
						if (string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Diablo") or string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Deandre") or string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Urban")) then
							if (game:GetService("Workspace").Enemies:FindFirstChild("Diablo") or game:GetService("Workspace").Enemies:FindFirstChild("Deandre") or game:GetService("Workspace").Enemies:FindFirstChild("Urban")) then
								for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
									if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
										if ((v.Name == "Diablo") or (v.Name == "Deandre") or (v.Name == "Urban")) then
											repeat
												wait(_G.Fast_Delay);
												AttackNoCoolDown();
												EquipTool(SelectWeapon);
												AutoHaki();
												Tween2(v.HumanoidRootPart.CFrame * Pos);
												v.Humanoid.WalkSpeed = 0;
												v.HumanoidRootPart.CanCollide = false;
												v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
											until (_G.AutoElite == false) or (v.Humanoid.Health <= 0) or not v.Parent 
										end
									end
								end
							elseif game:GetService("ReplicatedStorage"):FindFirstChild("Diablo") then
								Tween2(game:GetService("ReplicatedStorage"):FindFirstChild("Diablo").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
							elseif game:GetService("ReplicatedStorage"):FindFirstChild("Deandre") then
								Tween2(game:GetService("ReplicatedStorage"):FindFirstChild("Deandre").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
							elseif game:GetService("ReplicatedStorage"):FindFirstChild("Urban") then
								Tween2(game:GetService("ReplicatedStorage"):FindFirstChild("Urban").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
							end
						end
					else
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("EliteHunter");
					end
				end);
			end
		end
	end);
end
if Sea3 then
	local AutoMysticIsland = Tabs.Sea:AddSection("Đảo Bí Ẩn");
	local StatusMirage = Tabs.Sea:AddParagraph({Title="Trạng Thái",Content=""});
	task.spawn(function()
		while task.wait() do
			pcall(function()
				local moonTextureId = game:GetService("Lighting").Sky.MoonTextureId;
				if (moonTextureId == "http://www.roblox.com/asset/?id=9709149431") then
					FullMoonStatus = "100%";
				elseif (moonTextureId == "http://www.roblox.com/asset/?id=9709149052") then
					FullMoonStatus = "75%";
				elseif (moonTextureId == "http://www.roblox.com/asset/?id=9709143733") then
					FullMoonStatus = "50%";
				elseif (moonTextureId == "http://www.roblox.com/asset/?id=9709150401") then
					FullMoonStatus = "25%";
				elseif (moonTextureId == "http://www.roblox.com/asset/?id=9709149680") then
					FullMoonStatus = "15%";
				else
					FullMoonStatus = "0%";
				end
			end);
		end
	end);
	task.spawn(function()
		while task.wait() do
			pcall(function()
				if game.Workspace.Map:FindFirstChild("MysticIsland") then
					MirageStatus = "✅️";
				else
					MirageStatus = "❌️";
				end
			end);
		end
	end);
	spawn(function()
		pcall(function()
			while wait() do
				StatusMirage:SetDesc("Đảo Bí Ẩn: " .. MirageStatus .. " | Trăng Tròn: " .. FullMoonStatus);
			end
		end);
	end);
	Tabs.Sea:AddButton({Title="Bay Đến Chỗ Cao",Description="",Callback=function()
		TweenToHighestPoint();
	end});
	function TweenToHighestPoint()
		local HighestPoint = getHighestPoint();
		if HighestPoint then
			Tween2(HighestPoint.CFrame * CFrame.new(0, 211.88, 0));
		end
	end
	function getHighestPoint()
		if not game.Workspace.Map:FindFirstChild("MysticIsland") then
			return nil;
		end
		for _, v in pairs(game:GetService("Workspace").Map.MysticIsland:GetDescendants()) do
			if v:IsA("MeshPart") then
				if (v.MeshId == "rbxassetid://6745037796") then
					return v;
				end
			end
		end
	end
end
local ToggleTpAdvanced = Tabs.Sea:AddToggle("ToggleTpAdvanced", {Title="Bay Đến Advanced Fruit Dealer",Description="",Default=false});
ToggleTpAdvanced:OnChanged(function(Value)
	_G.AutoTpAdvanced = Value;
end);
spawn(function()
	while wait() do
		if _G.AutoTpAdvanced then
			local advancedFruitDealer = game.ReplicatedStorage.NPCs:FindFirstChild("Advanced Fruit Dealer");
			if (advancedFruitDealer and advancedFruitDealer:IsA("Model")) then
				local dealerPosition = advancedFruitDealer.PrimaryPart and advancedFruitDealer.PrimaryPart.Position;
				if dealerPosition then
					Tween2(CFrame.new(dealerPosition));
				end
			end
		end
	end
end);
local ToggleTweenGear = Tabs.Sea:AddToggle("ToggleTweenGear", {Title="Bay Đến Bánh Răng",Description="",Default=false});
ToggleTweenGear:OnChanged(function(Value)
	_G.TweenToGear = Value;
end);
Options.ToggleTweenGear:SetValue(false);
spawn(function()
	pcall(function()
		while wait() do
			if _G.TweenToGear then
				if game:GetService("Workspace").Map:FindFirstChild("MysticIsland") then
					for i, v in pairs(game:GetService("Workspace").Map.MysticIsland:GetChildren()) do
						if v:IsA("MeshPart") then
							if (v.Material == Enum.Material.Neon) then
								Tween2(v.CFrame);
							end
						end
					end
				end
			end
		end
	end);
end);
local Togglelockmoon = Tabs.Sea:AddToggle("Togglelockmoon", {Title="Nhìn Trăng Và Dùng Tộc",Description="",Default=false});
Togglelockmoon:OnChanged(function(Value)
	_G.AutoLockMoon = Value;
end);
Options.Togglelockmoon:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.AutoLockMoon then
				local moonDir = game.Lighting:GetMoonDirection();
				local lookAtPos = game.Workspace.CurrentCamera.CFrame.p + (moonDir * 100);
				game.Workspace.CurrentCamera.CFrame = CFrame.lookAt(game.Workspace.CurrentCamera.CFrame.p, lookAtPos);
			end
		end);
	end
end);
spawn(function()
	while wait() do
		pcall(function()
			if _G.AutoLockMoon then
				game:GetService("ReplicatedStorage").Remotes.CommE:FireServer("ActivateAbility");
			end
		end);
	end
end);
local Toggle = Tabs.New:AddToggle("Toggle", {Title="Cày Summon Token",Description="",Default=false});
Toggle:OnChanged(function(Value)
	_G.SummerToken = Value;
end);
spawn(function()
    while wait() do
        if _G.SummerToken and Sea3 then
            pcall(function()
                if game:GetService("Workspace").Enemies:FindFirstChild("Fishman Captain") then
                    for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
                        if v.Name == "Fishman Raider" then
                            if v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 then
                                repeat task.wait()
                                    bringmob = true;
		                			AutoHaki();
		                			EquipTool(SelectWeapon);
                                    Tween(v.HumanoidRootPart.CFrame * CFrame.new(0, 30, 0))
                                    v.HumanoidRootPart.CanCollide = false
                                    v.Humanoid.WalkSpeed = 0
                                    v.Head.CanCollide = false
                                    FarmPos = v.HumanoidRootPart.CFrame;
			                		MonFarm = v.Name;
                                until not _G.SummerToken or not v.Parent or v.Humanoid.Health <= 0
                            end
                        end
                    end
                else
                    Tween(CFrame.new(-10961.0126953125, 331.7977600097656, -8914.29296875))
                    if game:GetService("ReplicatedStorage"):FindFirstChild("Fishman Raider") then
                        Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Fishman Raider").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2))
                    end
                end
            end)
        end
    end
end)
local Toggle = Tabs.New:AddToggle("Toggle", {Title="Tự Động Kéo Cá",Description="",Default=false});
Toggle:OnChanged(function(Value)
	_G.KeoCa = Value;
end);
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

local CONFIG = {
    SCAN_RANGE = 30,
    SCAN_STEP = 2,
    WAIT_TIME = 0.2,
    SKILL_THRESHOLD = 0.9,
    FISHING_POSITION = Vector3.new(-378, 11, 5202),
    MAX_REELING_ATTEMPTS = 50
}

local function PressKey(key)
    VirtualInputManager:SendKeyEvent(true, key, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, key, false, game)
end

local function ClickAtPosition(x, y)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.1)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

local function GetFishingRod()
    if Character and Character:FindFirstChild("Fishing Rod") then
        return Character["Fishing Rod"]
    end
    return nil
end

local function FindNearestFishingSpot()
    local nearest, nearestDist = nil, CONFIG.SCAN_RANGE
    for x = -CONFIG.SCAN_RANGE, CONFIG.SCAN_RANGE, CONFIG.SCAN_STEP do
        for z = -CONFIG.SCAN_RANGE, CONFIG.SCAN_RANGE, CONFIG.SCAN_STEP do
            local position = HumanoidRootPart.Position + Vector3.new(x, 0, z)
            local distance = (position - HumanoidRootPart.Position).Magnitude
            local raycast = workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0))
            if raycast and raycast.Material == Enum.Material.Water then
                if distance < nearestDist then
                    nearest = position
                    nearestDist = distance
                end
            end
        end
    end
    return nearest
end

local function MoveTo(position)
    if HumanoidRootPart then
        HumanoidRootPart.CFrame = CFrame.new(position)
        task.wait(1)
    end
end

local function AimAtTarget(targetPosition)
    if not targetPosition then return false end
    local direction = (targetPosition - HumanoidRootPart.Position).Unit
    HumanoidRootPart.CFrame = CFrame.lookAt(HumanoidRootPart.Position, 
        HumanoidRootPart.Position + Vector3.new(direction.X, 0, direction.Z))
    workspace.CurrentCamera.CFrame = CFrame.lookAt(
        workspace.CurrentCamera.CFrame.Position, 
        targetPosition
    )
    local screenPos, onScreen = workspace.CurrentCamera:WorldToViewportPoint(targetPosition)
    if not onScreen then
        workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * CFrame.new(0, 50, 0)
        screenPos = workspace.CurrentCamera:WorldToViewportPoint(targetPosition)
    end
    return screenPos.X, screenPos.Y, true
end

local function HandleFishingStates()
    local rod = GetFishingRod()
    if not rod then return false end
    local rodState = rod:GetAttribute("State")
    local nearest = FindNearestFishingSpot()
    if not nearest then return false end
    if table.find({"ReleaseCasting", "Launching", "Waiting"}, rodState) then
        return true
    elseif table.find({"ReeledIn", "Biting"}, rodState) then
        ClickAtPosition(0, 0)
        task.wait(2)
        return true
    elseif rodState == "StartCasting" or Character:FindFirstChild("Fishing Cast Meter") then
        local x, y, success = AimAtTarget(nearest)
        if success then
            ClickAtPosition(x, y)
            task.wait(2)
        end
        return true
    elseif rodState == "ReelingIn" then
        local attempts = 0
        repeat
            task.wait(1)
            attempts = attempts + 1
            pcall(function()
                return ReplicatedStorage.FishReplicated.FishingRequest:InvokeServer("Catch", 1)
            end)
            rod = GetFishingRod()
        until (rod and rod:GetAttribute("State") ~= "ReelingIn") or attempts >= CONFIG.MAX_REELING_ATTEMPTS
        return true
    end
    return false
end

local function AutoFish()
    MoveTo(CONFIG.FISHING_POSITION)
    while _G.KeoCa do
        local rod = GetFishingRod()
        if rod then
            local skillCharge = rod:GetAttribute("SkillChargeAlpha")
            if skillCharge and skillCharge >= CONFIG.SKILL_THRESHOLD then
                PressKey(Enum.KeyCode.Z)
            end
            if LocalPlayer.PlayerGui:FindFirstChild("Fishing Reeling") then
                if not HandleFishingStates() then
                    task.wait(1)
                end
            else
                pcall(function()
                    return ReplicatedStorage.FishReplicated.FishingRequest:InvokeServer("Catch", 1)
                end)
            end
        else
            task.wait(2)
        end
        task.wait(CONFIG.WAIT_TIME)
    end
end
spawn(function()
    while task.wait(1) do
        if _G.KeoCa then
            AutoFish()
        end
    end
end)
local ToggleAutoSaber = Tabs.ITM:AddToggle("ToggleAutoSaber", {Title="Saber",Description="",Default=false});
ToggleAutoSaber:OnChanged(function(Value)
	_G.Auto_Saber = Value;
end);
Options.ToggleAutoSaber:SetValue(false);
spawn(function()
	while task.wait() do
		if (_G.Auto_Saber and (game.Players.LocalPlayer.Data.Level.Value >= 200)) then
			pcall(function()
				if (game:GetService("Workspace").Map.Jungle.Final.Part.Transparency == 0) then
					if (game:GetService("Workspace").Map.Jungle.QuestPlates.Door.Transparency == 0) then
						if ((CFrame.new(-1612.55884, 36.9774132, 148.719543, 0.37091279, 3.071715e-9, -0.928667724, 3.970995e-8, 1, 1.9167935e-8, 0.928667724, -4.398698e-8, 0.37091279).Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 100) then
							Tween(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame);
							wait(1);
							game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").Map.Jungle.QuestPlates.Plate1.Button.CFrame;
							wait(1);
							game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").Map.Jungle.QuestPlates.Plate2.Button.CFrame;
							wait(1);
							game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").Map.Jungle.QuestPlates.Plate3.Button.CFrame;
							wait(1);
							game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").Map.Jungle.QuestPlates.Plate4.Button.CFrame;
							wait(1);
							game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").Map.Jungle.QuestPlates.Plate5.Button.CFrame;
							wait(1);
						else
							Tween(CFrame.new(-1612.55884, 36.9774132, 148.719543, 0.37091279, 3.071715e-9, -0.928667724, 3.970995e-8, 1, 1.9167935e-8, 0.928667724, -4.398698e-8, 0.37091279));
						end
					elseif (game:GetService("Workspace").Map.Desert.Burn.Part.Transparency == 0) then
						if (game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Torch") or game.Players.LocalPlayer.Character:FindFirstChild("Torch")) then
							EquipTool("Torch");
							Tween(CFrame.new(1114.61475, 5.04679728, 4350.22803, -0.648466587, -1.2879909e-9, 0.761243105, -5.706529e-10, 1, 1.2058454e-9, -0.761243105, 3.4754488e-10, -0.648466587));
						else
							Tween(CFrame.new(-1610.00757, 11.5049858, 164.001587, 0.984807551, -0.167722285, -0.0449818149, 0.17364943, 0.951244235, 0.254912198, 0.00003423728, -0.258850515, 0.965917408));
						end
					elseif (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "SickMan") ~= 0) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "GetCup");
						wait(0.5);
						EquipTool("Cup");
						wait(0.5);
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "FillCup", game:GetService("Players").LocalPlayer.Character.Cup);
						wait(0);
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "SickMan");
					elseif (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "RichSon") == nil) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "RichSon");
					elseif (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "RichSon") == 0) then
						if (game:GetService("Workspace").Enemies:FindFirstChild("Mob Leader") or game:GetService("ReplicatedStorage"):FindFirstChild("Mob Leader")) then
							Tween(CFrame.new(-2967.59521, -4.91089821, 5328.70703, 0.342208564, -0.0227849055, 0.939347804, 0.0251603816, 0.999569714, 0.0150796166, -0.939287126, 0.0184739735, 0.342634559));
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if (v.Name == "Mob Leader") then
									if game:GetService("Workspace").Enemies:FindFirstChild("Mob Leader [Lv. 120] [Boss]") then
										if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
											repeat
												task.wait(_G.Fast_Delay);
												AutoHaki();
												EquipTool(SelectWeapon);
												v.HumanoidRootPart.CanCollide = false;
												v.Humanoid.WalkSpeed = 0;
												v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
												Tween(v.HumanoidRootPart.CFrame * Pos);
												AttackNoCoolDown();
											until (v.Humanoid.Health <= 0) or not _G.Auto_Saber 
										end
									end
									if game:GetService("ReplicatedStorage"):FindFirstChild("Mob Leader") then
										Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Mob Leader").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
									end
								end
							end
						end
					elseif (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "RichSon") == 1) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "RichSon");
						wait(0.5);
						EquipTool("Relic");
						wait(0.5);
						Tween(CFrame.new(-1404.91504, 29.9773273, 3.80598116, 0.876514494, 5.6690688e-9, 0.481375456, 2.53852e-8, 1, -5.799956e-8, -0.481375456, 6.3057264e-8, 0.876514494));
					end
				elseif (game:GetService("Workspace").Enemies:FindFirstChild("Saber Expert") or game:GetService("ReplicatedStorage"):FindFirstChild("Saber Expert")) then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
							if (v.Name == "Saber Expert") then
								repeat
									task.wait(_G.Fast_Delay);
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
									v.HumanoidRootPart.Transparency = 1;
									v.Humanoid.JumpPower = 0;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.CanCollide = false;
									bringmob = true;
									FarmPos = v.HumanoidRootPart.CFrame;
									MonFarm = v.Name;
									AttackNoCoolDown();
								until (v.Humanoid.Health <= 0) or not _G.Auto_Saber 
								bringmob = true;
								if (v.Humanoid.Health <= 0) then
									game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ProQuestProgress", "PlaceRelic");
								end
							end
						end
					end
				end
			end);
		end
	end
end);
local ToggleAutoPoleV1 = Tabs.ITM:AddToggle("ToggleAutoPoleV1", {Title="Pole V1",Description="",Default=false});
ToggleAutoPoleV1:OnChanged(function(Value)
	_G.Auto_PoleV1 = Value;
end);
Options.ToggleAutoPoleV1:SetValue(false);
local PolePos = CFrame.new(-7748.0185546875, 5606.80615234375, -2305.898681640625);
spawn(function()
	while wait() do
		if _G.Auto_PoleV1 then
			pcall(function()
				if game:GetService("Workspace").Enemies:FindFirstChild("Thunder God") then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (v.Name == "Thunder God") then
							if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
								repeat
									task.wait(_G.Fast_Delay);
									AutoHaki();
									EquipTool(SelectWeapon);
									v.HumanoidRootPart.CanCollide = false;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									AttackNoCoolDown();
								until not _G.Auto_PoleV1 or not v.Parent or (v.Humanoid.Health <= 0) 
							end
						end
					end
				elseif ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - PolePos.Position).Magnitude < 1500) then
					Tween(PolePos);
				end
				Tween(CFrame.new(-7748.0185546875, 5606.80615234375, -2305.898681640625));
				if game:GetService("ReplicatedStorage"):FindFirstChild("Thunder God") then
					Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Thunder God").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
				end
			end);
		end
	end
end);
local ToggleAutoSaw = Tabs.ITM:AddToggle("ToggleAutoSaw", {Title="Cưa Cá Mập",Description="",Default=false});
ToggleAutoSaw:OnChanged(function(Value)
	_G.Auto_Saw = Value;
end);
Options.ToggleAutoSaw:SetValue(false);
local PolePos = CFrame.new(-690.33081054688, 15.09425163269, 1582.2380371094);
spawn(function()
	while wait() do
		if _G.Auto_Saw then
			pcall(function()
				if game:GetService("Workspace").Enemies:FindFirstChild("The Saw") then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (v.Name == "The Saw") then
							if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
								repeat
									task.wait(_G.Fast_Delay);
									AutoHaki();
									EquipTool(SelectWeapon);
									v.HumanoidRootPart.CanCollide = false;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									AttackNoCoolDown();
								until not _G.Auto_Saw or not v.Parent or (v.Humanoid.Health <= 0) 
							end
						end
					end
				elseif ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - PolePos.Position).Magnitude < 1500) then
					Tween(PolePos);
				end
				Tween(CFrame.new(-690.33081054688, 15.09425163269, 1582.2380371094));
				if game:GetService("ReplicatedStorage"):FindFirstChild("The Saw") then
					Tween(game:GetService("ReplicatedStorage"):FindFirstChild("The Saw").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
				end
			end);
		end
	end
end);
local ToggleAutoWarden = Tabs.ITM:AddToggle("ToggleAutoWarden", {Title="Kiếm Quản Ngục",Description="",Default=false});
ToggleAutoWarden:OnChanged(function(Value)
	_G.Auto_Warden = Value;
end);
Options.ToggleAutoWarden:SetValue(false);
local WardenPos = CFrame.new(5186.14697265625, 24.86684226989746, 832.1885375976562);
spawn(function()
	while wait() do
		if _G.Auto_Warden then
			pcall(function()
				if game:GetService("Workspace").Enemies:FindFirstChild("Chief Warden") then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (v.Name == "Chief Warden") then
							if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
								repeat
									task.wait(_G.Fast_Delay);
									AutoHaki();
									EquipTool(SelectWeapon);
									v.HumanoidRootPart.CanCollide = false;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									AttackNoCoolDown();
								until not _G.Auto_Warden or not v.Parent or (v.Humanoid.Health <= 0) 
							end
						end
					end
				elseif ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - WardenPos.Position).Magnitude < 1500) then
					Tween(WardenPos);
				end
				Tween(CFrame.new(5186.14697265625, 24.86684226989746, 832.1885375976562));
				if game:GetService("ReplicatedStorage"):FindFirstChild("Chief Warden") then
					Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Chief Warden").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
				end
			end);
		end
	end
end);
if Sea3 then
	local ToggleHallow = Tabs.ITM:AddToggle("ToggleHallow", {Title="Lưỡi Hái",Description="",Default=false});
	ToggleHallow:OnChanged(function(Value)
		AutoHallowSycthe = Value;
	end);
	Options.ToggleHallow:SetValue(false);
	spawn(function()
		while wait() do
			if AutoHallowSycthe then
				pcall(function()
					if game:GetService("Workspace").Enemies:FindFirstChild("Soul Reaper") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if string.find(v.Name, "Soul Reaper") then
								repeat
									wait(_G.Fast_Delay);
									AttackNoCoolDown();
									AutoHaki();
									EquipTool(SelectWeapon);
									v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.Transparency = 1;
									sethiddenproperty(game.Players.LocalPlayer, "SimulationRadius", math.huge);
								until (v.Humanoid.Health <= 0) or (AutoHallowSycthe == false) 
							end
						end
					elseif (game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Hallow Essence") or game:GetService("Players").LocalPlayer.Character:FindFirstChild("Hallow Essence")) then
						repeat
							Tween(CFrame.new(-8932.322265625, 146.83154296875, 6062.55078125));
							wait();
						until (CFrame.new(-8932.322265625, 146.83154296875, 6062.55078125).Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 8 
						wait();
						EquipTool("Hallow Essence");
					elseif game:GetService("ReplicatedStorage"):FindFirstChild("Soul Reaper") then
						Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Soul Reaper").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
					else
					end
				end);
			end
		end
	end);
	spawn(function()
		while wait() do
			if AutoHallowSycthe then
				local args = {[1]="Bones",[2]="Buy",[3]=1,[4]=1};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
			end
		end
	end);
	local ToggleYama = Tabs.ITM:AddToggle("ToggleYama", {Title="Yama",Description="",Default=false});
	ToggleYama:OnChanged(function(Value)
		_G.AutoYama = Value;
	end);
	Options.ToggleYama:SetValue(false);
	spawn(function()
		while wait() do
			if _G.AutoYama then
				if (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("EliteHunter", "Progress") >= 30) then
					repeat
						wait();
						fireclickdetector(game:GetService("Workspace").Map.Waterfall.SealedKatana.Handle.ClickDetector);
					until game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Yama") or not _G.AutoYama 
				end
			end
		end
	end);
	local ToggleTushita = Tabs.ITM:AddToggle("ToggleTushita", {Title="Tushita",Description="",Default=false});
	ToggleTushita:OnChanged(function(Value)
		AutoTushita = Value;
	end);
	Options.ToggleTushita:SetValue(false);
	spawn(function()
		while wait() do
			if AutoTushita then
				if game:GetService("Workspace").Enemies:FindFirstChild("Longma") then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if ((v.Name == ("Longma" or (v.Name == "Longma"))) and (v.Humanoid.Health > 0) and v:IsA("Model") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart")) then
							repeat
								wait(_G.Fast_Delay);
								AttackNoCoolDown();
								AutoHaki();
								if not game.Players.LocalPlayer.Character:FindFirstChild(SelectWeapon) then
									wait();
									EquipTool(SelectWeapon);
								end
								FarmPos = v.HumanoidRootPart.CFrame;
								v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
								v.Humanoid.JumpPower = 0;
								v.Humanoid.WalkSpeed = 0;
								v.HumanoidRootPart.CanCollide = false;
								v.Humanoid:ChangeState(11);
								Tween(v.HumanoidRootPart.CFrame * Pos);
							until not AutoTushita or not v.Parent or (v.Humanoid.Health <= 0) 
						end
					end
				else
					Tween(CFrame.new(-10238.875976563, 389.7912902832, -9549.7939453125));
				end
			end
		end
	end);
	local ToggleHoly = Tabs.ITM:AddToggle("ToggleHoly", {Title="Đốt Đuốc",Description="",Default=false});
	ToggleHoly:OnChanged(function(Value)
		_G.Auto_Holy_Torch = Value;
	end);
	Options.ToggleHoly:SetValue(false);
	spawn(function()
		while wait() do
			if _G.Auto_Holy_Torch then
				pcall(function()
					wait();
					repeat
						Tween(CFrame.new(-10752, 417, -9366));
						wait();
					until not _G.Auto_Holy_Torch or ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(-10752, 417, -9366)).Magnitude <= 10) 
					wait();
					repeat
						Tween(CFrame.new(-11672, 334, -9474));
						wait();
					until not _G.Auto_Holy_Torch or ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(-11672, 334, -9474)).Magnitude <= 10) 
					wait();
					repeat
						Tween(CFrame.new(-12132, 521, -10655));
						wait();
					until not _G.Auto_Holy_Torch or ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(-12132, 521, -10655)).Magnitude <= 10) 
					wait();
					repeat
						Tween(CFrame.new(-13336, 486, -6985));
						wait();
					until not _G.Auto_Holy_Torch or ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(-13336, 486, -6985)).Magnitude <= 10) 
					wait();
					repeat
						Tween(CFrame.new(-13489, 332, -7925));
						wait();
					until not _G.Auto_Holy_Torch or ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(-13489, 332, -7925)).Magnitude <= 10) 
				end);
			end
		end
	end);
end
local ToggleAutoCanvander = Tabs.ITM:AddToggle("ToggleAutoCanvander", {Title="Canvander",Description="",Default=false});
ToggleAutoCanvander:OnChanged(function(Value)
	_G.Auto_Canvander = Value;
end);
Options.ToggleAutoCanvander:SetValue(false);
local PolePos = CFrame.new(5311.07421875, 426.0243835449219, 165.12762451171875);
spawn(function()
	while wait() do
		if _G.Auto_Canvander then
			pcall(function()
				if game:GetService("Workspace").Enemies:FindFirstChild("Beautiful Pirate") then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (v.Name == "Beautiful Pirate") then
							if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
								repeat
									task.wait(_G.Fast_Delay);
									AutoHaki();
									EquipTool(SelectWeapon);
									v.HumanoidRootPart.CanCollide = false;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									AttackNoCoolDown();
								until not _G.Auto_Canvander or not v.Parent or (v.Humanoid.Health <= 0) 
							end
						end
					end
				elseif ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - PolePos.Position).Magnitude < 1500) then
					Tween(PolePos);
				end
				Tween(CFrame.new(5311.07421875, 426.0243835449219, 165.12762451171875));
				if game:GetService("ReplicatedStorage"):FindFirstChild("Beautiful Pirate") then
					Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Beautiful Pirate").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
				end
			end);
		end
	end
end);
local ToggleAutoMusketeerHat = Tabs.ITM:AddToggle("ToggleAutoMusketeerHat", {Title="Mũ Lính Ngự Lâm",Description="",Default=false});
ToggleAutoMusketeerHat:OnChanged(function(Value)
	_G.Auto_MusketeerHat = Value;
end);
Options.ToggleAutoMusketeerHat:SetValue(false);
spawn(function()
	pcall(function()
		while wait(0.1) do
			if _G.Auto_MusketeerHat then
				if ((game:GetService("Players").LocalPlayer.Data.Level.Value >= 1800) and (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CitizenQuestProgress").KilledBandits == false)) then
					if (string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Forest Pirate") and string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "50") and (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == true)) then
						if game:GetService("Workspace").Enemies:FindFirstChild("Forest Pirate") then
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if (v.Name == "Forest Pirate") then
									repeat
										task.wait(_G.Fast_Delay);
										pcall(function()
											EquipTool(SelectWeapon);
											AutoHaki();
											v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
											Tween(v.HumanoidRootPart.CFrame * Pos);
											v.HumanoidRootPart.CanCollide = false;
											AttackNoCoolDown();
											PosMon = v.HumanoidRootPart.CFrame;
											MonFarm = v.Name;
											bringmob = true;
										end);
									until (_G.Auto_MusketeerHat == false) or not v.Parent or (v.Humanoid.Health <= 0) or (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == false) 
									bringmob = false;
								end
							end
						else
							bringmob = false;
							Tween(CFrame.new(-13206.452148438, 425.89199829102, -7964.5537109375));
						end
					else
						Tween(CFrame.new(-12443.8671875, 332.40396118164, -7675.4892578125));
						if ((Vector3.new(-12443.8671875, 332.40396118164, -7675.4892578125) - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 30) then
							wait(1.5);
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StartQuest", "CitizenQuest", 1);
						end
					end
				elseif ((game:GetService("Players").LocalPlayer.Data.Level.Value >= 1800) and (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CitizenQuestProgress").KilledBoss == false)) then
					if (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible and string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Captain Elephant") and (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == true)) then
						if game:GetService("Workspace").Enemies:FindFirstChild("Captain Elephant") then
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if (v.Name == "Captain Elephant") then
									OldCFrameElephant = v.HumanoidRootPart.CFrame;
									repeat
										task.wait(_G.Fast_Delay);
										pcall(function()
											EquipTool(SelectWeapon);
											AutoHaki();
											v.HumanoidRootPart.CanCollide = false;
											v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
											Tween(v.HumanoidRootPart.CFrame * Pos);
											v.HumanoidRootPart.CanCollide = false;
											v.HumanoidRootPart.CFrame = OldCFrameElephant;
											AttackNoCoolDown();
										end);
									until (_G.Auto_MusketeerHat == false) or (v.Humanoid.Health <= 0) or not v.Parent or (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible == false) 
								end
							end
						else
							Tween(CFrame.new(-13374.889648438, 421.27752685547, -8225.208984375));
						end
					else
						Tween(CFrame.new(-12443.8671875, 332.40396118164, -7675.4892578125));
						if ((CFrame.new(-12443.8671875, 332.40396118164, -7675.4892578125).Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 4) then
							wait(1.5);
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CitizenQuestProgress", "Citizen");
						end
					end
				elseif ((game:GetService("Players").LocalPlayer.Data.Level.Value >= 1800) and (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CitizenQuestProgress", "Citizen") == 2)) then
					Tween(CFrame.new(-12512.138671875, 340.39279174805, -9872.8203125));
				end
			end
		end
	end);
end);
local ToggleAutoObservationV2 = Tabs.ITM:AddToggle("ToggleAutoObservationV2", {Title="Haki Quan Sát V2",Description="",Default=false});
ToggleAutoObservationV2:OnChanged(function(Value)
	_G.Auto_ObservationV2 = Value;
end);
Options.ToggleAutoObservationV2:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.Auto_ObservationV2 then
				if (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CitizenQuestProgress", "Citizen") == 3) then
					_G.Auto_MusketeerHat = false;
					if (game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Banana") and game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Apple") and game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Pineapple")) then
						repeat
							Tween(CFrame.new(-12444.78515625, 332.40396118164, -7673.1806640625));
							wait();
						until not _G.Auto_ObservationV2 or ((game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(-12444.78515625, 332.40396118164, -7673.1806640625)).Magnitude <= 10) 
						wait(0.5);
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CitizenQuestProgress", "Citizen");
					elseif (game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Fruit Bowl") or game:GetService("Players").LocalPlayer.Character:FindFirstChild("Fruit Bowl")) then
						repeat
							Tween(CFrame.new(-10920.125, 624.20275878906, -10266.995117188));
							wait();
						until not _G.Auto_ObservationV2 or ((game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(-10920.125, 624.20275878906, -10266.995117188)).Magnitude <= 10) 
						wait(0.5);
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("KenTalk2", "Start");
						wait(1);
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("KenTalk2", "Buy");
					else
						for i, v in pairs(game:GetService("Workspace"):GetDescendants()) do
							if ((v.Name == "Apple") or (v.Name == "Banana") or (v.Name == "Pineapple")) then
								v.Handle.CFrame = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(0, 1, 10);
								wait();
								firetouchinterest(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart, v.Handle, 0);
								wait();
							end
						end
					end
				else
					_G.Auto_MusketeerHat = true;
				end
			end
		end);
	end
end);
local ToggleAutoRainbowHaki = Tabs.ITM:AddToggle("ToggleAutoRainbowHaki", {Title="Haki 7 Màu",Description="",Default=false});
ToggleAutoRainbowHaki:OnChanged(function(Value)
	_G.Auto_RainbowHaki = Value;
end);
Options.ToggleAutoRainbowHaki:SetValue(false);
spawn(function()
	pcall(function()
		while wait(0.1) do
			if _G.Auto_RainbowHaki then
				if not game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible then
					Tween(CFrame.new(-11892.0703125, 930.57672119141, -8760.1591796875));
					if ((Vector3.new(-11892.0703125, 930.57672119141, -8760.1591796875) - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 30) then
						wait(1.5);
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("HornedMan", "Bet");
					end
				elseif (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible and string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Stone")) then
					if game:GetService("Workspace").Enemies:FindFirstChild("Stone") then
						for _, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Stone") then
								OldCFrameRainbow = v.HumanoidRootPart.CFrame;
								repeat
									task.wait(_G.Fast_Delay);
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.CanCollide = false;
									v.HumanoidRootPart.CFrame = OldCFrameRainbow;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									AttackNoCoolDown();
								until not _G.Auto_RainbowHaki or (v.Humanoid.Health <= 0) or not v.Parent or not game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible 
							end
						end
					else
						Tween(CFrame.new(-1086.11621, 38.8425903, 6768.71436));
					end
				elseif (game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible and string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Hydra Leader")) then
					if game:GetService("Workspace").Enemies:FindFirstChild("Hydra Leader") then
						for _, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Hydra Leader") then
								OldCFrameRainbow = v.HumanoidRootPart.CFrame;
								repeat
									task.wait(_G.Fast_Delay);
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.CanCollide = false;
									v.HumanoidRootPart.CFrame = OldCFrameRainbow;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									AttackNoCoolDown();
								until not _G.Auto_RainbowHaki or (v.Humanoid.Health <= 0) or not v.Parent or not game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible 
							end
						end
					else
						Tween(CFrame.new(5713.98877, 601.922974, 202.751251));
					end
				elseif string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Kilo Admiral") then
					if game:GetService("Workspace").Enemies:FindFirstChild("Kilo Admiral") then
						for _, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Kilo Admiral") then
								OldCFrameRainbow = v.HumanoidRootPart.CFrame;
								repeat
									task.wait(_G.Fast_Delay);
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.CanCollide = false;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									v.HumanoidRootPart.CFrame = OldCFrameRainbow;
									AttackNoCoolDown();
								until not _G.Auto_RainbowHaki or (v.Humanoid.Health <= 0) or not v.Parent or not game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible 
							end
						end
					else
						Tween(CFrame.new(2877.61743, 423.558685, -7207.31006));
					end
				elseif string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Captain Elephant") then
					if game:GetService("Workspace").Enemies:FindFirstChild("Captain Elephant") then
						for _, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Captain Elephant") then
								OldCFrameRainbow = v.HumanoidRootPart.CFrame;
								repeat
									task.wait(_G.Fast_Delay);
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.CanCollide = false;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									v.HumanoidRootPart.CFrame = OldCFrameRainbow;
									AttackNoCoolDown();
								until not _G.Auto_RainbowHaki or (v.Humanoid.Health <= 0) or not v.Parent or not game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible 
							end
						end
					else
						Tween(CFrame.new(-13485.0283, 331.709259, -8012.4873));
					end
				elseif string.find(game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "Beautiful Pirate") then
					if game:GetService("Workspace").Enemies:FindFirstChild("Beautiful Pirate") then
						for _, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Beautiful Pirate") then
								OldCFrameRainbow = v.HumanoidRootPart.CFrame;
								repeat
									task.wait(_G.Fast_Delay);
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.CanCollide = false;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									v.HumanoidRootPart.CFrame = OldCFrameRainbow;
									AttackNoCoolDown();
								until not _G.Auto_RainbowHaki or (v.Humanoid.Health <= 0) or not v.Parent or not game:GetService("Players").LocalPlayer.PlayerGui.Main.Quest.Visible 
							end
						end
					else
						Tween(CFrame.new(5312.3598632813, 20.141201019287, -10.158538818359));
					end
				else
					Tween(CFrame.new(-11892.0703125, 930.57672119141, -8760.1591796875));
					if ((Vector3.new(-11892.0703125, 930.57672119141, -8760.1591796875) - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 30) then
						wait(1.5);
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("HornedMan", "Bet");
					end
				end
			end
		end
	end);
end);
local ToggleAutoSkullGuitar = Tabs.ITM:AddToggle("ToggleAutoSkullGuitar", {Title="Skull Guitar",Description="",Default=false});
ToggleAutoSkullGuitar:OnChanged(function(Value)
	_G.Auto_SkullGuitar = Value;
end);
Options.ToggleAutoSkullGuitar:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.Auto_SkullGuitar then
				if (GetWeaponInventory("Skull Guitar") == false) then
					if ((CFrame.new(-9681.458984375, 6.139880657196045, 6341.3720703125).Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 5000) then
						if game:GetService("Workspace").NPCs:FindFirstChild("Skeleton Machine") then
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("soulGuitarBuy", true);
						elseif (game:GetService("Workspace").Map["Haunted Castle"].Candle1.Transparency == 0) then
							if (game:GetService("Workspace").Map["Haunted Castle"].Placard1.Left.Part.Transparency == 0) then
								Quest2 = true;
								repeat
									wait();
									Tween(CFrame.new(-8762.69140625, 176.84783935546875, 6171.3076171875));
								until ((CFrame.new(-8762.69140625, 176.84783935546875, 6171.3076171875).Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 3) or not _G.Auto_SkullGuitar 
								wait(1);
								fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"].Placard7.Left.ClickDetector);
								wait(1);
								fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"].Placard6.Left.ClickDetector);
								wait(1);
								fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"].Placard5.Left.ClickDetector);
								wait(1);
								fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"].Placard4.Right.ClickDetector);
								wait(1);
								fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"].Placard3.Left.ClickDetector);
								wait(1);
								fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"].Placard2.Right.ClickDetector);
								wait(1);
								fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"].Placard1.Right.ClickDetector);
								wait(1);
							elseif game:GetService("Workspace").Map["Haunted Castle"].Tablet.Segment1:FindFirstChild("ClickDetector") then
								if game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part1:FindFirstChild("ClickDetector") then
									Quest4 = true;
									repeat
										wait();
										Tween(CFrame.new(-9553.5986328125, 65.62338256835938, 6041.58837890625));
									until ((CFrame.new(-9553.5986328125, 65.62338256835938, 6041.58837890625).Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 3) or not _G.Auto_SkullGuitar 
									wait(1);
									Tween(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part3.CFrame);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part3.ClickDetector);
									wait(1);
									Tween(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part4.CFrame);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part4.ClickDetector);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part4.ClickDetector);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part4.ClickDetector);
									wait(1);
									Tween(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part6.CFrame);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part6.ClickDetector);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part6.ClickDetector);
									wait(1);
									Tween(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part8.CFrame);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part8.ClickDetector);
									wait(1);
									Tween(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part10.CFrame);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part10.ClickDetector);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part10.ClickDetector);
									wait(1);
									fireclickdetector(game:GetService("Workspace").Map["Haunted Castle"]["Lab Puzzle"].ColorFloor.Model.Part10.ClickDetector);
								else
									Quest3 = true;
								end
							else
								if game:GetService("Workspace").NPCs:FindFirstChild("Ghost") then
									local args = {[1]="GuitarPuzzleProgress",[2]="Ghost"};
									game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
								end
								if game.Workspace.Enemies:FindFirstChild("Living Zombie") then
									for i, v in pairs(game.Workspace.Enemies:GetChildren()) do
										if (v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and (v.Humanoid.Health > 0)) then
											if (v.Name == "Living Zombie") then
												EquipTool(SelectWeapon);
												v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
												v.HumanoidRootPart.Transparency = 1;
												v.Humanoid.JumpPower = 0;
												v.Humanoid.WalkSpeed = 0;
												v.HumanoidRootPart.CanCollide = false;
												v.HumanoidRootPart.CFrame = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(0, 20, 0);
												Tween(CFrame.new(-10160.787109375, 138.6616973876953, 5955.03076171875));
												game:GetService("VirtualUser"):CaptureController();
												game:GetService("VirtualUser"):Button1Down(Vector2.new(1280, 672));
											end
										end
									end
								else
									Tween(CFrame.new(-10160.787109375, 138.6616973876953, 5955.03076171875));
								end
							end
						elseif string.find(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("gravestoneEvent", 2), "Error") then
							Tween(CFrame.new(-8653.2060546875, 140.98487854003906, 6160.033203125));
						elseif string.find(game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("gravestoneEvent", 2), "Nothing") then
							Tween("Wait Full Moon");
						else
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("gravestoneEvent", 2, true);
						end
					else
						Tween(CFrame.new(-9681.458984375, 6.139880657196045, 6341.3720703125));
					end
				end
			end
		end);
	end
end);
local ToggleAutoBuddy = Tabs.ITM:AddToggle("ToggleAutoBuddy", {Title="Kiếm Buddy",Description="",Default=false});
ToggleAutoBuddy:OnChanged(function(Value)
	_G.Auto_Buddy = Value;
end);
Options.ToggleAutoBuddy:SetValue(false);
local BuddyPos = CFrame.new(-731.2034301757812, 381.5658874511719, -11198.4951171875);
spawn(function()
	while wait() do
		if _G.Auto_Buddy then
			pcall(function()
				if game:GetService("Workspace").Enemies:FindFirstChild("Cake Queen") then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (v.Name == "Cake Queen") then
							if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
								repeat
									task.wait(_G.Fast_Delay);
									AutoHaki();
									EquipTool(SelectWeapon);
									v.HumanoidRootPart.CanCollide = false;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									AttackNoCoolDown();
								until not _G.Auto_Buddy or not v.Parent or (v.Humanoid.Health <= 0) 
							end
						end
					end
				elseif ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - BuddyPos.Position).Magnitude < 1500) then
					Tween(BuddyPos);
				end
				Tween(CFrame.new(-731.2034301757812, 381.5658874511719, -11198.4951171875));
				if game:GetService("ReplicatedStorage"):FindFirstChild("Cake Queen") then
					Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Cake Queen").HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
				end
			end);
		end
	end
end);
local ToggleAutoDualKatana = Tabs.ITM:AddToggle("ToggleAutoDualKatana", {Title="Song Kiếm",Description="",Default=false});
ToggleAutoDualKatana:OnChanged(function(Value)
	_G.Auto_DualKatana = Value;
end);
Options.ToggleAutoDualKatana:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.Auto_DualKatana then
				if (game.Players.LocalPlayer.Character:FindFirstChild("Tushita") or game.Players.LocalPlayer.Backpack:FindFirstChild("Tushita") or game.Players.LocalPlayer.Character:FindFirstChild("Yama") or game.Players.LocalPlayer.Backpack:FindFirstChild("Yama")) then
					if (game.Players.LocalPlayer.Character:FindFirstChild("Tushita") or game.Players.LocalPlayer.Backpack:FindFirstChild("Tushita")) then
						if game.Players.LocalPlayer.Backpack:FindFirstChild("Tushita") then
							EquipTool("Tushita");
						end
					elseif (game.Players.LocalPlayer.Character:FindFirstChild("Yama") or game.Players.LocalPlayer.Backpack:FindFirstChild("Yama")) then
						if game.Players.LocalPlayer.Backpack:FindFirstChild("Yama") then
							EquipTool("Yama");
						end
					end
				else
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("LoadItem", "Tushita");
				end
			end
		end);
	end
end);
spawn(function()
	while wait() do
		pcall(function()
			if _G.Auto_DualKatana then
				if (GetMaterial("Alucard Fragment") == 0) then
					Auto_Quest_Yama_1 = true;
					Auto_Quest_Yama_2 = false;
					Auto_Quest_Yama_3 = false;
					Auto_Quest_Tushita_1 = false;
					Auto_Quest_Tushita_2 = false;
					Auto_Quest_Tushita_3 = false;
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "Progress", "Evil");
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "StartTrial", "Evil");
				elseif (GetMaterial("Alucard Fragment") == 1) then
					Auto_Quest_Yama_1 = false;
					Auto_Quest_Yama_2 = true;
					Auto_Quest_Yama_3 = false;
					Auto_Quest_Tushita_1 = false;
					Auto_Quest_Tushita_2 = false;
					Auto_Quest_Tushita_3 = false;
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "Progress", "Evil");
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "StartTrial", "Evil");
				elseif (GetMaterial("Alucard Fragment") == 2) then
					Auto_Quest_Yama_1 = false;
					Auto_Quest_Yama_2 = false;
					Auto_Quest_Yama_3 = true;
					Auto_Quest_Tushita_1 = false;
					Auto_Quest_Tushita_2 = false;
					Auto_Quest_Tushita_3 = false;
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "Progress", "Evil");
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "StartTrial", "Evil");
				elseif (GetMaterial("Alucard Fragment") == 3) then
					Auto_Quest_Yama_1 = false;
					Auto_Quest_Yama_2 = false;
					Auto_Quest_Yama_3 = false;
					Auto_Quest_Tushita_1 = true;
					Auto_Quest_Tushita_2 = false;
					Auto_Quest_Tushita_3 = false;
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "Progress", "Good");
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "StartTrial", "Good");
				elseif (GetMaterial("Alucard Fragment") == 4) then
					Auto_Quest_Yama_1 = false;
					Auto_Quest_Yama_2 = false;
					Auto_Quest_Yama_3 = false;
					Auto_Quest_Tushita_1 = false;
					Auto_Quest_Tushita_2 = true;
					Auto_Quest_Tushita_3 = false;
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "Progress", "Good");
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "StartTrial", "Good");
				elseif (GetMaterial("Alucard Fragment") == 5) then
					Auto_Quest_Yama_1 = false;
					Auto_Quest_Yama_2 = false;
					Auto_Quest_Yama_3 = false;
					Auto_Quest_Tushita_1 = false;
					Auto_Quest_Tushita_2 = false;
					Auto_Quest_Tushita_3 = true;
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "Progress", "Good");
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "StartTrial", "Good");
				elseif (GetMaterial("Alucard Fragment") == 6) then
					if (game:GetService("Workspace").Enemies:FindFirstChild("Cursed Skeleton Boss [Lv. 2025] [Boss]") or game:GetService("Workspace").ReplicatedStorage:FindFirstChild("Cursed Skeleton Boss [Lv. 2025] [Boss]")) then
						Auto_Quest_Yama_1 = false;
						Auto_Quest_Yama_2 = false;
						Auto_Quest_Yama_3 = false;
						Auto_Quest_Tushita_1 = false;
						Auto_Quest_Tushita_2 = false;
						Auto_Quest_Tushita_3 = false;
						if (game:GetService("Workspace").Enemies:FindFirstChild("Cursed Skeleton Boss [Lv. 2025] [Boss]") or game:GetService("Workspace").Enemies:FindFirstChild("Cursed Skeleton [Lv. 2200]")) then
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if ((v.Name == "Cursed Skeleton Boss") or (v.Name == "Cursed Skeleton")) then
									if (v.Humanoid.Health > 0) then
										EquipTool(Sword);
										Tween(v.HumanoidRootPart.CFrame * pos);
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										v.HumanoidRootPart.Transparency = 1;
										v.Humanoid.JumpPower = 0;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.CanCollide = false;
										bringmob = true;
										FarmPos = v.HumanoidRootPart.CFrame;
										MonFarm = v.Name;
										AttackNoCoolDown();
									end
								end
							end
						end
					elseif ((CFrame.new(-12361.7060546875, 603.3547973632812, -6550.5341796875).Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 100) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "Progress", "Good");
						wait(1);
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "Progress", "Evil");
						wait(1);
						Tween(CFrame.new(-12361.7060546875, 603.3547973632812, -6550.5341796875));
						wait(1.5);
						game:GetService("VirtualInputManager"):SendKeyEvent(true, "E", false, game);
						wait(1.5);
						Tween(CFrame.new(-12253.5419921875, 598.8999633789062, -6546.8388671875));
					else
						Tween(CFrame.new(-12361.7060546875, 603.3547973632812, -6550.5341796875));
					end
				end
			end
		end);
	end
end);
spawn(function()
	while wait() do
		if Auto_Quest_Yama_1 then
			pcall(function()
				if game:GetService("Workspace").Enemies:FindFirstChild("Mythological Pirate") then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (v.Name == "Mythological Pirate") then
							repeat
								wait();
								Tween(v.HumanoidRootPart.CFrame * CFrame.new(0, 0, -2));
							until (_G.Auto_DualKatana == false) or (Auto_Quest_Yama_1 == false) 
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CDKQuest", "StartTrial", "Evil");
						end
					end
				else
					Tween(CFrame.new(-13451.46484375, 543.712890625, -6961.0029296875));
				end
			end);
		end
	end
end);
spawn(function()
	while wait() do
		pcall(function()
			if Auto_Quest_Yama_2 then
				for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
					if v:FindFirstChild("HazeESP") then
						v.HazeESP.Size = UDim2.new(50, 50, 50, 50);
						v.HazeESP.MaxDistance = "inf";
					end
				end
				for i, v in pairs(game:GetService("ReplicatedStorage"):GetChildren()) do
					if v:FindFirstChild("HazeESP") then
						v.HazeESP.Size = UDim2.new(50, 50, 50, 50);
						v.HazeESP.MaxDistance = "inf";
					end
				end
			end
		end);
	end
end);
spawn(function()
	while wait() do
		pcall(function()
			for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
				if (Auto_Quest_Yama_2 and v:FindFirstChild("HazeESP") and ((v.HumanoidRootPart.Position - FarmPossEsp.Position).magnitude <= 300)) then
					v.HumanoidRootPart.CFrame = FarmPossEsp;
					v.HumanoidRootPart.CanCollide = false;
					v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
					if not v.HumanoidRootPart:FindFirstChild("BodyVelocity") then
						local vc = Instance.new("BodyVelocity", v.HumanoidRootPart);
						vc.MaxForce = Vector3.new(1, 1, 1) * math.huge;
						vc.Velocity = Vector3.new(0, 0, 0);
					end
				end
			end
		end);
	end
end);
spawn(function()
	while wait() do
		if Auto_Quest_Yama_2 then
			pcall(function()
				for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
					if v:FindFirstChild("HazeESP") then
						repeat
							wait();
							if ((v.HumanoidRootPart.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 2000) then
								Tween(v.HumanoidRootPart.CFrame * Pos);
							else
								EquipTool(Sword);
								Tween(v.HumanoidRootPart.CFrame * Pos);
								v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
								v.HumanoidRootPart.Transparency = 1;
								v.Humanoid.JumpPower = 0;
								v.Humanoid.WalkSpeed = 0;
								v.HumanoidRootPart.CanCollide = false;
								FarmPos = v.HumanoidRootPart.CFrame;
								MonFarm = v.Name;
								AttackNoCoolDown();
								if ((v.Humanoid.Health <= 0) and v.Humanoid:FindFirstChild("Animator")) then
									v.Humanoid.Animator:Destroy();
								end
							end
						until (_G.Auto_DualKatana == false) or (Auto_Quest_Yama_2 == false) or not v.Parent or (v.Humanoid.Health <= 0) or not v:FindFirstChild("HazeESP") 
					else
						for x, y in pairs(game:GetService("ReplicatedStorage"):GetChildren()) do
							if y:FindFirstChild("HazeESP") then
								if ((y.HumanoidRootPart.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 2000) then
									Tween(y.HumanoidRootPart.CFrameMon * CFrame.new(2, 20, 2));
								else
									Tween(y.HumanoidRootPart.CFrame * CFrame.new(2, 20, 2));
								end
							end
						end
					end
				end
			end);
		end
	end
end);
spawn(function()
	while wait() do
		if Auto_Quest_Yama_3 then
			pcall(function()
				if game.Players.LocalPlayer.Backpack:FindFirstChild("Hallow Essence") then
					Tween(game:GetService("Workspace").Map["Haunted Castle"].Summoner.Detection.CFrame);
				elseif game:GetService("Workspace").Map:FindFirstChild("HellDimension") then
					repeat
						wait();
						if (game:GetService("Workspace").Enemies:FindFirstChild("Cursed Skeleton [Lv. 2200]") or game:GetService("Workspace").Enemies:FindFirstChild("Cursed Skeleton [Lv. 2200] [Boss]") or game:GetService("Workspace").Enemies:FindFirstChild("Hell's Messenger [Lv. 2200] [Boss]")) then
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if ((v.Name == "Cursed Skeleton") or (v.Name == "Cursed Skeleton") or (v.Name == "Hell's Messenger")) then
									if (v.Humanoid.Health > 0) then
										repeat
											wait();
											EquipTool(Sword);
											Tween(v.HumanoidRootPart.CFrame * Pos);
											v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
											v.HumanoidRootPart.Transparency = 1;
											v.Humanoid.JumpPower = 0;
											v.Humanoid.WalkSpeed = 0;
											v.HumanoidRootPart.CanCollide = false;
											FarmPos = v.HumanoidRootPart.CFrame;
											MonFarm = v.Name;
											AttackNoCoolDown();
											if ((v.Humanoid.Health <= 0) and v.Humanoid:FindFirstChild("Animator")) then
												v.Humanoid.Animator:Destroy();
											end
										until (v.Humanoid.Health <= 0) or not v.Parent or (Auto_Quest_Yama_3 == false) 
									end
								end
							end
						else
							wait(5);
							Tween(game:GetService("Workspace").Map.HellDimension.Torch1.CFrame);
							wait(1.5);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, "E", false, game);
							wait(1.5);
							Tweem(game:GetService("Workspace").Map.HellDimension.Torch2.CFrame);
							wait(1.5);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, "E", false, game);
							wait(1.5);
							Tween(game:GetService("Workspace").Map.HellDimension.Torch3.CFrame);
							wait(1.5);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, "E", false, game);
							wait(1.5);
							Tween(game:GetService("Workspace").Map.HellDimension.Exit.CFrame);
						end
					until (_G.Auto_DualKatana == false) or (Auto_Quest_Yama_3 == false) or (GetMaterial("Alucard Fragment") == 3) 
				elseif (game:GetService("Workspace").Enemies:FindFirstChild("Soul Reaper") or game.ReplicatedStorage:FindFirstChild("Soul Reaper [Lv. 2100] [Raid Boss]")) then
					if game:GetService("Workspace").Enemies:FindFirstChild("Soul Reaper") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Soul Reaper") then
								if (v.Humanoid.Health > 0) then
									repeat
										wait();
										Tween(v.HumanoidRootPart.CFrame * Pos);
									until (_G.Auto_DualKatana == false) or (Auto_Quest_Yama_3 == false) or game:GetService("Workspace").Map:FindFirstChild("HellDimension") 
								end
							end
						end
					else
						Tween(CFrame.new(-9570.033203125, 315.9346923828125, 6726.89306640625));
					end
				else
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Bones", "Buy", 1, 1);
				end
			end);
		end
	end
end);
spawn(function()
	while wait() do
		if Auto_Quest_Tushita_1 then
			Tween(CFrame.new(-9546.990234375, 21.139892578125, 4686.1142578125));
			wait(5);
			Tween(CFrame.new(-6120.0576171875, 16.455780029296875, -2250.697265625));
			wait(5);
			Tween(CFrame.new(-9533.2392578125, 7.254445552825928, -8372.69921875));
		end
	end
end);
spawn(function()
	while wait() do
		if Auto_Quest_Tushita_2 then
			pcall(function()
				if ((CFrame.new(-5539.3115234375, 313.800537109375, -2972.372314453125).Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 500) then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (Auto_Quest_Tushita_2 and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and (v.Humanoid.Health > 0)) then
							if ((v.HumanoidRootPart.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude < 2000) then
								repeat
									wait();
									EquipTool(Sword);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
									v.HumanoidRootPart.Transparency = 1;
									v.Humanoid.JumpPower = 0;
									v.Humanoid.WalkSpeed = 0;
									v.HumanoidRootPart.CanCollide = false;
									FarmPos = v.HumanoidRootPart.CFrame;
									MonFarm = v.Name;
									AttackNoCoolDown();
									if ((v.Humanoid.Health <= 0) and v.Humanoid:FindFirstChild("Animator")) then
										v.Humanoid.Animator:Destroy();
									end
								until (v.Humanoid.Health <= 0) or not v.Parent or (Auto_Quest_Tushita_2 == false) 
							end
						end
					end
				else
					Tween(CFrame.new(-5545.1240234375, 313.800537109375, -2976.616455078125));
				end
			end);
		end
	end
end);
spawn(function()
	while wait() do
		if Auto_Quest_Tushita_3 then
			pcall(function()
				if (game:GetService("Workspace").Enemies:FindFirstChild("Cake Queen") or game.ReplicatedStorage:FindFirstChild("Cake Queen [Lv. 2175] [Boss]")) then
					if game:GetService("Workspace").Enemies:FindFirstChild("Cake Queen") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Cake Queen") then
								if (v.Humanoid.Health > 0) then
									repeat
										wait();
										EquipTool(Sword);
										Tween(v.HumanoidRootPart.CFrame * Pos);
										v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
										v.HumanoidRootPart.Transparency = 1;
										v.Humanoid.JumpPower = 0;
										v.Humanoid.WalkSpeed = 0;
										v.HumanoidRootPart.CanCollide = false;
										FarmPos = v.HumanoidRootPart.CFrame;
										MonFarm = v.Name;
										AttackNoCoolDown();
										if ((v.Humanoid.Health <= 0) and v.Humanoid:FindFirstChild("Animator")) then
											v.Humanoid.Animator:Destroy();
										end
									until (_G.Auto_DualKatana == false) or (Auto_Quest_Tushita_3 == false) or game:GetService("Workspace").Map:FindFirstChild("HeavenlyDimension") 
								end
							end
						end
					else
						Tween(CFrame.new(-709.3132934570312, 381.6005859375, -11011.396484375));
					end
				elseif game:GetService("Workspace").Map:FindFirstChild("HeavenlyDimension") then
					repeat
						wait();
						if (game:GetService("Workspace").Enemies:FindFirstChild("Cursed Skeleton [Lv. 2200]") or game:GetService("Workspace").Enemies:FindFirstChild("Cursed Skeleton [Lv. 2200] [Boss]") or game:GetService("Workspace").Enemies:FindFirstChild("Heaven's Guardian [Lv. 2200] [Boss]")) then
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if ((v.Name == "Cursed Skeleton") or (v.Name == "Cursed Skeleton") or (v.Name == "Heaven's Guardian")) then
									if (v.Humanoid.Health > 0) then
										repeat
											wait();
											EquipTool(Sword);
											Tween(v.HumanoidRootPart.CFrame * Pos);
											v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
											v.HumanoidRootPart.Transparency = 1;
											v.Humanoid.JumpPower = 0;
											v.Humanoid.WalkSpeed = 0;
											v.HumanoidRootPart.CanCollide = false;
											FarmPos = v.HumanoidRootPart.CFrame;
											MonFarm = v.Name;
											AttackNoCoolDown();
											if ((v.Humanoid.Health <= 0) and v.Humanoid:FindFirstChild("Animator")) then
												v.Humanoid.Animator:Destroy();
											end
										until (v.Humanoid.Health <= 0) or not v.Parent or (Auto_Quest_Tushita_3 == false) 
									end
								end
							end
						else
							wait(5);
							Tween(game:GetService("Workspace").Map.HeavenlyDimension.Torch1.CFrame);
							wait(1.5);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, "E", false, game);
							wait(1.5);
							Tween(game:GetService("Workspace").Map.HeavenlyDimension.Torch2.CFrame);
							wait(1.5);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, "E", false, game);
							wait(1.5);
							Tween(game:GetService("Workspace").Map.HeavenlyDimension.Torch3.CFrame);
							wait(1.5);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, "E", false, game);
							wait(1.5);
							Tween(game:GetService("Workspace").Map.HeavenlyDimension.Exit.CFrame);
						end
					until not _G.Auto_DualKatana or not Auto_Quest_Tushita_3 or (GetMaterial("Alucard Fragment") == 6) 
				end
			end);
		end
	end
end);
if Sea2 then
	local ToggleFactory = Tabs.ITM:AddToggle("ToggleFactory", {Title="Đấm Nhà Máy",Description="",Default=false});
	ToggleFactory:OnChanged(function(Value)
		_G.Factory = Value;
	end);
	Options.ToggleFactory:SetValue(false);
	spawn(function()
		while wait() do
			if _G.Factory then
				if game.Workspace.Enemies:FindFirstChild("Core") then
					for i, v in pairs(game.Workspace.Enemies:GetChildren()) do
						if ((v.Name == "Core") and (v.Humanoid.Health > 0)) then
							repeat
								wait(_G.Fast_Delay);
								AttackNoCoolDown();
								repeat
									Tween(CFrame.new(448.46756, 199.356781, -441.389252));
									wait();
								until not _G.Factory or ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(448.46756, 199.356781, -441.389252)).Magnitude <= 10) 
								EquipTool(SelectWeapon);
								AutoHaki();
								Tween(v.HumanoidRootPart.CFrame * Pos);
								v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
								v.HumanoidRootPart.Transparency = 1;
								v.Humanoid.JumpPower = 0;
								v.Humanoid.WalkSpeed = 0;
								v.HumanoidRootPart.CanCollide = false;
								FarmPos = v.HumanoidRootPart.CFrame;
								MonFarm = v.Name;
							until not v.Parent or (v.Humanoid.Health <= 0) or (_G.Factory == false) 
						end
					end
				elseif game.ReplicatedStorage:FindFirstChild("Core") then
					repeat
						Tween(CFrame.new(448.46756, 199.356781, -441.389252));
						wait();
					until not _G.Factory or ((game.Players.LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(448.46756, 199.356781, -441.389252)).Magnitude <= 10) 
				end
			end
		end
	end);
end
local ToggleAutoFarmSwan = Tabs.ITM:AddToggle("ToggleAutoFarmSwan", {Title="Đấm Swan",Description="",Default=false});
ToggleAutoFarmSwan:OnChanged(function(Value)
	_G.Auto_FarmSwan = Value;
end);
Options.ToggleAutoFarmSwan:SetValue(false);
spawn(function()
	pcall(function()
		while wait() do
			if _G.AutoFarmSwan then
				if game:GetService("Workspace").Enemies:FindFirstChild("Don Swan") then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if ((v.Name == "Don Swan") and (v.Humanoid.Health > 0) and v:IsA("Model") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart")) then
							repeat
								task.wait();
								pcall(function()
									AutoHaki();
									EquipTool(SelectWeapon);
									v.HumanoidRootPart.CanCollide = false;
									v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									AttackNoCoolDown();
								end);
							until (_G.AutoFarmSwan == false) or (v.Humanoid.Health <= 0) 
						end
					end
				else
					repeat
						task.wait();
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(2284.912109375, 15.537666320801, 905.48291015625));
					until ((CFrame.new(2284.912109375, 15.537666320801, 905.48291015625).Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 4) or (_G.AutoFarmSwan == false) 
				end
			end
		end
	end);
end);
local ToggleAutoRengoku = Tabs.ITM:AddToggle("ToggleAutoRengoku", {Title="Rengoku",Description="",Default=false});
ToggleAutoRengoku:OnChanged(function(Value)
	_G.Auto_Regoku = Value;
end);
Options.ToggleAutoRengoku:SetValue(false);
spawn(function()
	pcall(function()
		while wait() do
			if _G.Auto_Regoku then
				if (game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Hidden Key") or game:GetService("Players").LocalPlayer.Character:FindFirstChild("Hidden Key")) then
					EquipTool("Hidden Key");
					Tween(CFrame.new(6571.1201171875, 299.23028564453, -6967.841796875));
				elseif (game:GetService("Workspace").Enemies:FindFirstChild("Snow Lurker") or game:GetService("Workspace").Enemies:FindFirstChild("Arctic Warrior")) then
					for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
						if (((v.Name == "Snow Lurker") or (v.Name == "Arctic Warrior")) and (v.Humanoid.Health > 0)) then
							repeat
								task.wait(_G.Fast_Delay);
								EquipTool(SelectWeapon);
								AutoHaki();
								v.HumanoidRootPart.CanCollide = false;
								v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
								FarmPos = v.HumanoidRootPart.CFrame;
								MonFarm = v.Name;
								Tween(v.HumanoidRootPart.CFrame * Pos);
								AttackNoCoolDown();
								bringmob = true;
							until game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Hidden Key") or (_G.Auto_Regoku == false) or not v.Parent or (v.Humanoid.Health <= 0) 
							bringmob = false;
						end
					end
				else
					bringmob = false;
					Tween(CFrame.new(5439.716796875, 84.420944213867, -6715.1635742188));
				end
			end
		end
	end);
end);
if (Sea2 or Sea3) then
	local ToggleHakiColor = Tabs.ITM:AddToggle("ToggleHakiColor", {Title="Mua Màu Haki",Description="",Default=false});
	ToggleHakiColor:OnChanged(function(Value)
		_G.Auto_Buy_Enchancement = Value;
	end);
	Options.ToggleHakiColor:SetValue(false);
	spawn(function()
		while wait() do
			if _G.Auto_Buy_Enchancement then
				local args = {[1]="ColorsDealer",[2]="2"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
			end
		end
	end);
end
if Sea2 then
	local ToggleSwordLengend = Tabs.Main:AddToggle("ToggleSwordLengend", {Title="Mua Kiếm Huyền Thoại",Description="",Default=false});
	ToggleSwordLengend:OnChanged(function(Value)
		_G.BuyLengendSword = Value;
	end);
	Options.ToggleSwordLengend:SetValue(false);
	spawn(function()
		while wait() do
			pcall(function()
				if (_G.BuyLengendSword or Triple_A) then
					local args = {[1]="LegendarySwordDealer",[2]="2"};
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				else
					wait();
				end
			end);
		end
	end);
end
if Sea2 then
	local ToggleEvoRace = Tabs.Main:AddToggle("ToggleEvoRace", {Title="Nâng Tộc V2",Description="",Default=false});
	ToggleEvoRace:OnChanged(function(Value)
		_G.AutoEvoRace = Value;
	end);
	Options.ToggleEvoRace:SetValue(false);
	spawn(function()
		pcall(function()
			while wait(0.1) do
				if _G.AutoEvoRace then
					if not game:GetService("Players").LocalPlayer.Data.Race:FindFirstChild("Evolved") then
						if (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Alchemist", "1") == 0) then
							Tween(CFrame.new(-2779.83521, 72.9661407, -3574.02002, -0.730484903, 6.390141e-8, -0.68292886, 3.5996322e-8, 1, 5.5066703e-8, 0.68292886, 1.5642467e-8, -0.730484903));
							if ((Vector3.new(-2779.83521, 72.9661407, -3574.02002) - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 4) then
								wait(1.3);
								game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Alchemist", "2");
							end
						elseif (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Alchemist", "1") == 1) then
							pcall(function()
								if (not game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Flower 1") and not game:GetService("Players").LocalPlayer.Character:FindFirstChild("Flower 1")) then
									Tween(game:GetService("Workspace").Flower1.CFrame);
								elseif (not game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Flower 2") and not game:GetService("Players").LocalPlayer.Character:FindFirstChild("Flower 2")) then
									Tween(game:GetService("Workspace").Flower2.CFrame);
								elseif (not game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Flower 3") and not game:GetService("Players").LocalPlayer.Character:FindFirstChild("Flower 3")) then
									if game:GetService("Workspace").Enemies:FindFirstChild("Zombie") then
										for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
											if (v.Name == "Zombie") then
												repeat
													task.wait(_G.Fast_Delay);
													AutoHaki();
													EquipTool(SelectWeapon);
													Tween(v.HumanoidRootPart.CFrame * Pos);
													v.HumanoidRootPart.CanCollide = false;
													v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
													AttackNoCoolDown();
													FarmPos = v.HumanoidRootPart.CFrame;
													MonFarm = v.Name;
													bringmob = true;
												until game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Flower 3") or not v.Parent or (v.Humanoid.Health <= 0) or (_G.AutoEvoRace == false) 
												bringmob = false;
											end
										end
									else
										Tween(CFrame.new(-5685.9233398438, 48.480125427246, -853.23724365234));
									end
								end
							end);
						elseif (game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Alchemist", "1") == 2) then
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Alchemist", "3");
						end
					end
				end
			end
		end);
	end);
end
local ToggleAutoT = Tabs.Setting:AddToggle("ToggleAutoT", {Title="Bật Tộc V3",Description="",Default=false});
ToggleAutoT:OnChanged(function(Value)
	_G.AutoT = Value;
end);
Options.ToggleAutoT:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.AutoT then
				game:GetService("ReplicatedStorage").Remotes.CommE:FireServer("ActivateAbility");
			end
		end);
	end
end);
local ToggleAutoY = Tabs.Setting:AddToggle("ToggleAutoY", {Title="Bật Tộc V4",Description="",Default=false});
ToggleAutoY:OnChanged(function(Value)
	_G.AutoY = Value;
end);
Options.ToggleAutoY:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.AutoY then
				game:GetService("VirtualInputManager"):SendKeyEvent(true, "Y", false, game);
				wait();
				game:GetService("VirtualInputManager"):SendKeyEvent(false, "Y", false, game);
			end
		end);
	end
end);
local ToggleAutoKen = Tabs.Setting:AddToggle("ToggleAutoKen", {Title="Bật Haki Quan Sât",Description="",Default=false});
ToggleAutoKen:OnChanged(function(Value)
	_G.AutoKen = Value;
	if Value then
		game:GetService("ReplicatedStorage").Remotes.CommE:FireServer("Ken", true);
	else
		game:GetService("ReplicatedStorage").Remotes.CommE:FireServer("Ken", false);
	end
end);
Options.ToggleAutoKen:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.AutoKen then
				game:GetService("ReplicatedStorage").Remotes.CommE:FireServer("Ken", true);
			end
		end);
	end
end);
local ToggleSaveSpawn = Tabs.Setting:AddToggle("ToggleSaveSpawn", {Title="Lưu Điểm Hồi Sinh",Description="",Default=false});
ToggleSaveSpawn:OnChanged(function(Value)
	_G.SaveSpawn = Value;
	if Value then
		local args = {[1]="SetSpawnPoint"};
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
	end
end);
Options.ToggleSaveSpawn:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.SaveSpawn then
				local args = {[1]="SetSpawnPoint"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
			end
		end);
	end
end);
local Camera = require(game.ReplicatedStorage.Util.CameraShaker);
Camera:Stop();
local ToggleBringMob = Tabs.Setting:AddToggle("ToggleBringMob", {Title="Gom Quái",Description="",Default=true});
ToggleBringMob:OnChanged(function(Value)
	_G.BringMob = Value;
end);
Options.ToggleBringMob:SetValue(true);
spawn(function()
	while wait() do
		pcall(function()
			for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
				if (_G.BringMob and bringmob) then
					if ((v.Name == MonFarm) and v:FindFirstChild("Humanoid") and (v.Humanoid.Health > 0)) then
						if (v.Name == "Factory Staff") then
							if ((v.HumanoidRootPart.Position - FarmPos.Position).Magnitude <= 1000000000) then
								v.Head.CanCollide = false;
								v.HumanoidRootPart.CanCollide = false;
								v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
								v.HumanoidRootPart.CFrame = FarmPos;
								if v.Humanoid:FindFirstChild("Animator") then
									v.Humanoid.Animator:Destroy();
								end
								sethiddenproperty(game.Players.LocalPlayer, "SimulationRadius", math.huge);
							end
						elseif (v.Name == MonFarm) then
							if ((v.HumanoidRootPart.Position - FarmPos.Position).Magnitude <= 1000000000) then
								v.HumanoidRootPart.CFrame = FarmPos;
								v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
								v.HumanoidRootPart.Transparency = 1;
								v.Humanoid.JumpPower = 0;
								v.Humanoid.WalkSpeed = 0;
								if v.Humanoid:FindFirstChild("Animator") then
									v.Humanoid.Animator:Destroy();
								end
								v.HumanoidRootPart.CanCollide = false;
								v.Head.CanCollide = false;
								v.Humanoid:ChangeState(11);
								v.Humanoid:ChangeState(14);
								sethiddenproperty(game.Players.LocalPlayer, "SimulationRadius", math.huge);
							end
						end
					end
				end
			end
		end);
	end
end);
local ToggleRemoveNotify = Tabs.Setting:AddToggle("ToggleRemoveNotify", {Title="Xóa Thông Báo",Description="",Default=false});
ToggleRemoveNotify:OnChanged(function(Value)
	RemoveNotify = Value;
end);
Options.ToggleRemoveNotify:SetValue(false);
spawn(function()
	while wait() do
		if RemoveNotify then
			game.Players.LocalPlayer.PlayerGui.Notifications.Enabled = false;
		else
			game.Players.LocalPlayer.PlayerGui.Notifications.Enabled = true;
		end
	end
end);
local ToggleWhite = Tabs.Setting:AddToggle("ToggleWhite", {Title="Màn Hình Trắng",Description="",Default=false});
ToggleWhite:OnChanged(function(Value)
	_G.WhiteScreen = Value;
	if (_G.WhiteScreen == true) then
		game:GetService("RunService"):Set3dRenderingEnabled(false);
	elseif (_G.WhiteScreen == false) then
		game:GetService("RunService"):Set3dRenderingEnabled(true);
	end
end);
Options.ToggleWhite:SetValue(false);
local SKill = Tabs.Setting:AddSection("Kĩ Năng Thông Thạo");
local ToggleZ = Tabs.Setting:AddToggle("ToggleZ", {Title="Kĩ Năng Z",Description="",Default=true});
ToggleZ:OnChanged(function(Value)
	SkillZ = Value;
end);
Options.ToggleZ:SetValue(true);
local ToggleX = Tabs.Setting:AddToggle("ToggleX", {Title="Kĩ Năng X",Description="",Default=true});
ToggleX:OnChanged(function(Value)
	SkillX = Value;
end);
Options.ToggleX:SetValue(true);
local ToggleC = Tabs.Setting:AddToggle("ToggleC", {Title="Kĩ Năng C",Description="",Default=true});
ToggleC:OnChanged(function(Value)
	SkillC = Value;
end);
Options.ToggleC:SetValue(true);
local ToggleV = Tabs.Setting:AddToggle("ToggleV", {Title="Kĩ Năng V",Description="",Default=true});
ToggleV:OnChanged(function(Value)
	SkillV = Value;
end);
Options.ToggleV:SetValue(true);
local ToggleF = Tabs.Setting:AddToggle("ToggleF", {Title="Kĩ Năng F",Description="",Default=false});
ToggleF:OnChanged(function(Value)
	SkillF = Value;
end);
Options.ToggleF:SetValue(true);
local Usser = Tabs.Status:AddParagraph({Title="Thông Tin",Content=("━━━━━━━━━━━━━━━━━━━━━\n" .. "Tên : " .. game.Players.LocalPlayer.DisplayName .. " (@" .. game.Players.LocalPlayer.Name .. ")\n" .. "Cấp : " .. game:GetService("Players").LocalPlayer.Data.Level.Value .. "\n" .. "Tiền : " .. game:GetService("Players").LocalPlayer.Data.Beli.Value .. "\n" .. "Điểm F : " .. game:GetService("Players").LocalPlayer.Data.Fragments.Value .. "\n" .. "Tiền Truy Nã : " .. game:GetService("Players").LocalPlayer.leaderstats["Bounty/Honor"].Value .. "\n" .. "Máu: " .. game.Players.LocalPlayer.Character.Humanoid.Health .. "/" .. game.Players.LocalPlayer.Character.Humanoid.MaxHealth .. "\n" .. "Năng Lượng : " .. game.Players.LocalPlayer.Character.Energy.Value .. "/" .. game.Players.LocalPlayer.Character.Energy.MaxValue .. "\n" .. "Tộc : " .. game:GetService("Players").LocalPlayer.Data.Race.Value .. "\n" .. "Trái : " .. game:GetService("Players").LocalPlayer.Data.DevilFruit.Value .. "\n" .. "━━━━━━━━━━━━━━━━━━━━━")});
local Time = Tabs.Status:AddParagraph({Title="Thời Gian",Content=""});
local function UpdateLocalTime()
	local date = os.date("*t");
	local hour = date.hour % 24;
	local ampm = ((hour < 12) and "AM") or "PM";
	local formattedTime = string.format("%02i:%02i:%02i %s", ((hour - 1) % 12) + 1, date.min, date.sec, ampm);
	local formattedDate = string.format("%02d/%02d/%04d", date.day, date.month, date.year);
	local LocalizationService = game:GetService("LocalizationService");
	local Players = game:GetService("Players");
	local player = Players.LocalPlayer;
	local name = player.Name;
	local regionCode = "Unknown";
	local success, code = pcall(function()
		return LocalizationService:GetCountryRegionForPlayerAsync(player);
	end);
	if success then
		regionCode = code;
	end
	Time:SetDesc(formattedDate .. "-" .. formattedTime .. " [" .. regionCode .. "]");
end
spawn(function()
	while true do
		UpdateLocalTime();
		game:GetService("RunService").RenderStepped:Wait();
	end
end);
local ServerTime = Tabs.Status:AddParagraph({Title="Thời Gian Máy Chủ",Content=""});
local function UpdateServerTime()
	local GameTime = math.floor(workspace.DistributedGameTime + 0.5);
	local Hour = math.floor(GameTime / (60 ^ 2)) % 24;
	local Minute = math.floor(GameTime / 60) % 60;
	local Second = GameTime % 60;
	ServerTime:SetDesc(string.format("%02d Tiếng-%02d Phút-%02d Giây", Hour, Minute, Second));
end
spawn(function()
	while task.wait() do
		pcall(UpdateServerTime);
	end
end);
local FrozenIsland = Tabs.Status:AddParagraph({Title="Đảo Leviathan",Content=""});
spawn(function()
	pcall(function()
		while wait() do
			if game:GetService("Workspace").Map:FindFirstChild("FrozenDimension") then
				FrozenIsland:SetDesc("✅");
			else
				FrozenIsland:SetDesc("❌");
			end
		end
	end);
end);
local Input = Tabs.Status:AddInput("Input", {Title="Job ID",Default="",Placeholder="Dán Job ID Vào Đây",Numeric=false,Finished=false,Callback=function(Value)
	_G.Job = Value;
end});
Tabs.Status:AddButton({Title="Bắt Đầu Tham Gia Job ID",Description="",Callback=function()
	game:GetService("TeleportService"):TeleportToPlaceInstance(game.placeId, _G.Job, game.Players.LocalPlayer);
end});
Tabs.Status:AddButton({Title="Sao Chép Job ID",Description="",Callback=function()
	setclipboard(tostring(game.JobId));
end});
local Toggle = Tabs.Status:AddToggle("MyToggle", {Title="Spam Tham Gia Job ID",Default=false});
Toggle:OnChanged(function(Value)
	_G.Join = Value;
end);
spawn(function()
	while wait() do
		if _G.Join then
			game:GetService("TeleportService"):TeleportToPlaceInstance(game.placeId, _G.Job, game.Players.LocalPlayer);
		end
	end
end);
local ToggleMelee = Tabs.Stats:AddToggle("ToggleMelee", {Title="Nâng Đấm",Description="",Default=false});
ToggleMelee:OnChanged(function(Value)
	_G.Auto_Stats_Melee = Value;
end);
Options.ToggleMelee:SetValue(false);
local ToggleDe = Tabs.Stats:AddToggle("ToggleDe", {Title="Nâng Máu",Description="",Default=false});
ToggleDe:OnChanged(function(Value)
	_G.Auto_Stats_Defense = Value;
end);
Options.ToggleDe:SetValue(false);
local ToggleSword = Tabs.Stats:AddToggle("ToggleSword", {Title="Nâng Kiếm",Description="",Default=false});
ToggleSword:OnChanged(function(Value)
	_G.Auto_Stats_Sword = Value;
end);
Options.ToggleSword:SetValue(false);
local ToggleGun = Tabs.Stats:AddToggle("ToggleGun", {Title="Nâng Súng",Description="",Default=false});
ToggleGun:OnChanged(function(Value)
	_G.Auto_Stats_Gun = Value;
end);
Options.ToggleGun:SetValue(false);
local ToggleFruit = Tabs.Stats:AddToggle("ToggleFruit", {Title="Nâng Trái",Description="",Default=false});
ToggleFruit:OnChanged(function(Value)
	_G.Auto_Stats_Devil_Fruit = Value;
end);
Options.ToggleFruit:SetValue(false);
spawn(function()
	while wait() do
		if _G.Auto_Stats_Devil_Fruit then
			local args = {[1]="AddPoint",[2]="Demon Fruit",[3]=3};
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
		end
	end
end);
spawn(function()
	while wait() do
		if _G.Auto_Stats_Gun then
			local args = {[1]="AddPoint",[2]="Gun",[3]=3};
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
		end
	end
end);
spawn(function()
	while wait() do
		if _G.Auto_Stats_Sword then
			local args = {[1]="AddPoint",[2]="Sword",[3]=3};
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
		end
	end
end);
spawn(function()
	while wait() do
		if _G.Auto_Stats_Defense then
			local args = {[1]="AddPoint",[2]="Defense",[3]=3};
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
		end
	end
end);
spawn(function()
	while wait() do
		if _G.Auto_Stats_Melee then
			local args = {[1]="AddPoint",[2]="Melee",[3]=3};
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
		end
	end
end);
local Playerslist = {};
for i, v in pairs(game:GetService("Players"):GetChildren()) do
	table.insert(Playerslist, v.Name);
end
local SelectedPly = Tabs.Player:AddDropdown("SelectedPly", {Title="Chọn Người Chơi",Description="",Values=Playerslist,Multi=false,Default=1});
SelectedPly:SetValue(_G.SelectPly);
SelectedPly:OnChanged(function(Value)
	_G.SelectPly = Value;
end);
Tabs.Player:AddButton({Title="Tải Lại Người Chơi",Description="",Callback=function()
	table.clear(Playerslist);
	for i, v in pairs(game:GetService("Players"):GetChildren()) do
		table.insert(Playerslist, v.Name);
	end
end});
local ToggleTeleport = Tabs.Player:AddToggle("ToggleTeleport", {Title="Bay Đến Người Chơi",Description="",Default=false});
ToggleTeleport:OnChanged(function(Value)
	_G.TeleportPly = Value;
	if (Value == false) then
		wait();
		AutoHaki();
		Tween2(game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame);
		wait();
	end
end);
Options.ToggleTeleport:SetValue(false);
spawn(function()
	while wait() do
		if _G.TeleportPly then
			pcall(function()
				if game.Players:FindFirstChild(_G.SelectPly) then
					Tween2(game.Players[_G.SelectPly].Character.HumanoidRootPart.CFrame);
				end
			end);
		end
	end
end);
local Mastery = Tabs.Player:AddSection("Khác");
local ToggleNoClip = Tabs.Player:AddToggle("ToggleNoClip", {Title="Đi Xuyên Tường",Description="",Default=true});
ToggleNoClip:OnChanged(function(value)
	_G.LOf = value;
end);
Options.ToggleNoClip:SetValue(true);
spawn(function()
	pcall(function()
		game:GetService("RunService").Stepped:Connect(function()
			if _G.LOf then
				for _, v in pairs(game.Players.LocalPlayer.Character:GetDescendants()) do
					if v:IsA("BasePart") then
						v.CanCollide = false;
					end
				end
			end
		end);
	end);
end);
local ToggleWalkonWater = Tabs.Player:AddToggle("ToggleWalkonWater", {Title="Đi Trên Nước",Description="",Default=true});
ToggleWalkonWater:OnChanged(function(Value)
	_G.WalkonWater = Value;
end);
Options.ToggleWalkonWater:SetValue(true);
spawn(function()
	while task.wait() do
		pcall(function()
			if _G.WalkonWater then
				game:GetService("Workspace").Map["WaterBase-Plane"].Size = Vector3.new(1000, 112, 1000);
			else
				game:GetService("Workspace").Map["WaterBase-Plane"].Size = Vector3.new(1000, 80, 1000);
			end
		end);
	end
end);
local ToggleEnablePvp = Tabs.Player:AddToggle("ToggleEnablePvp", {Title="Bật PVP",Description="",Default=false});
ToggleEnablePvp:OnChanged(function(Value)
	_G.EnabledPvP = Value;
end);
Options.ToggleEnablePvp:SetValue(false);
spawn(function()
	pcall(function()
		while wait() do
			if _G.EnabledPvP then
				if (game:GetService("Players").LocalPlayer.PlayerGui.Main.PvpDisabled.Visible == true) then
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("EnablePvp");
				end
			end
		end
	end);
end);
local Teleport = Tabs.Teleport:AddSection("Thế Giới");
local ToggleAutoSea2 = Tabs.Teleport:AddToggle("ToggleAutoSea2", {Title="Nhiệm Vụ Qua Biển 2",Description="",Default=false});
ToggleAutoSea2:OnChanged(function(Value)
	_G.Auto_Sea2 = Value;
end);
Options.ToggleAutoSea2:SetValue(false);
spawn(function()
	while wait() do
		if _G.Auto_Sea2 then
			pcall(function()
				local MyLevel = game:GetService("Players").LocalPlayer.Data.Level.Value;
				if ((MyLevel >= 700) and World1) then
					if ((game:GetService("Workspace").Map.Ice.Door.CanCollide == false) and (game:GetService("Workspace").Map.Ice.Door.Transparency == 1)) then
						local CFrame1 = CFrame.new(4849.29883, 5.65138149, 719.611877);
						repeat
							Tween(CFrame1);
							wait();
						until ((CFrame1.Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 3) or (_G.Auto_Sea2 == false) 
						wait(1.1);
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("DressrosaQuestProgress", "Detective");
						wait(0.5);
						EquipTool("Key");
						repeat
							Tween(CFrame.new(1347.7124, 37.3751602, -1325.6488));
							wait();
						until ((Vector3.new(1347.7124, 37.3751602, -1325.6488) - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 3) or (_G.Auto_Sea2 == false) 
						wait(0.5);
					elseif ((game:GetService("Workspace").Map.Ice.Door.CanCollide == false) and (game:GetService("Workspace").Map.Ice.Door.Transparency == 1)) then
						if game:GetService("Workspace").Enemies:FindFirstChild("Ice Admiral") then
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if (v.Name == "Ice Admiral") then
									if (not v.Humanoid.Health <= 0) then
										if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
											OldCFrameSecond = v.HumanoidRootPart.CFrame;
											repeat
												task.wait(_G.Fast_Delay);
												AutoHaki();
												EquipTool(SelectWeapon);
												v.HumanoidRootPart.CanCollide = false;
												v.Humanoid.WalkSpeed = 0;
												v.Head.CanCollide = false;
												v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
												v.HumanoidRootPart.CFrame = OldCFrameSecond;
												Tween(v.HumanoidRootPart.CFrame * Pos);
												AttackNoCoolDown();
												sethiddenproperty(game:GetService("Players").LocalPlayer, "SimulationRadius", math.huge);
											until not _G.Auto_Sea2 or not v.Parent or (v.Humanoid.Health <= 0) 
										end
									else
										game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TravelDressrosa");
									end
								end
							end
						elseif game:GetService("ReplicatedStorage"):FindFirstChild("Ice Admiral") then
							Tween(game:GetService("ReplicatedStorage"):FindFirstChild("Ice Admiral").HumanoidRootPart.CFrame * CFrame.new(5, 10, 7));
						end
					end
				end
			end);
		end
	end
end);
local ToggleAutoSea3 = Tabs.Teleport:AddToggle("ToggleAutoSea3", {Title="Nhiệm Vụ Qua Biển 3",Description="",Default=false});
ToggleAutoSea3:OnChanged(function(Value)
	_G.Auto_Sea3 = Value;
end);
Options.ToggleAutoSea3:SetValue(false);
spawn(function()
	while wait() do
		if _G.AutoSea3 then
			pcall(function()
				if ((game:GetService("Players").LocalPlayer.Data.Level.Value >= 1500) and World2) then
					_G.AutoLevel = false;
					if (game:GetService("ReplicatedStorage").Remotes['CommF_']:InvokeServer("ZQuestProgress", "General") == 0) then
						Tween(CFrame.new(-1926.3221435547, 12.819851875305, 1738.3092041016));
						if ((CFrame.new(-1926.3221435547, 12.819851875305, 1738.3092041016).Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 10) then
							wait(1.5);
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("ZQuestProgress", "Begin");
						end
						wait(1.8);
						if game:GetService("Workspace").Enemies:FindFirstChild("rip_indra") then
							for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
								if (v.Name == "rip_indra") then
									OldCFrameThird = v.HumanoidRootPart.CFrame;
									repeat
										task.wait(_G.Fast_Delay);
										AutoHaki();
										EquipTool(SelectWeapon);
										Tween(v.HumanoidRootPart.CFrame * Pos);
										v.HumanoidRootPart.CFrame = OldCFrameThird;
										v.HumanoidRootPart.Size = Vector3.new(50, 50, 50);
										v.HumanoidRootPart.CanCollide = false;
										v.Humanoid.WalkSpeed = 0;
										AttackNoCoolDown();
										game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TravelZou");
									until (_G.AutoSea3 == false) or (v.Humanoid.Health <= 0) or not v.Parent 
								end
							end
						elseif (not game:GetService("Workspace").Enemies:FindFirstChild("rip_indra") and ((CFrame.new(-26880.93359375, 22.848554611206, 473.18951416016).Position - game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 1000)) then
							Tween(CFrame.new(-26880.93359375, 22.848554611206, 473.18951416016));
						end
					end
				end
			end);
		end
	end
end);
Tabs.Teleport:AddButton({Title="Biến 1",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TravelMain");
end});
Tabs.Teleport:AddButton({Title="Biến 2",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TravelDressrosa");
end});
Tabs.Teleport:AddButton({Title="Biển 3",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TravelZou");
end});
local Mastery = Tabs.Teleport:AddSection("Đảo");
if Sea1 then
	IslandList = {"WindMill","Marine","Middle Town","Jungle","Pirate Village","Desert","Snow Island","MarineFord","Colosseum","Sky Island 1","Sky Island 2","Sky Island 3","Prison","Magma Village","Under Water Island","Fountain City","Shank Room","Mob Island"};
elseif Sea2 then
	IslandList = {"The Cafe","Frist Spot","Dark Area","Flamingo Mansion","Flamingo Room","Green Zone","Factory","Colossuim","Zombie Island","Two Snow Mountain","Punk Hazard","Cursed Ship","Ice Castle","Forgotten Island","Ussop Island","Mini Sky Island"};
elseif Sea3 then
	IslandList = {"Mansion","Port Town","Great Tree","Castle On The Sea","MiniSky","Hydra Island","Floating Turtle","Haunted Castle","Ice Cream Island","Peanut Island","Cake Island","Cocoa Island","Candy Island","Tiki Outpost"};
end
local DropdownIsland = Tabs.Teleport:AddDropdown("DropdownIsland", {Title="Chọn Đảo",Description="",Values=IslandList,Multi=false,Default=1});
DropdownIsland:SetValue(_G.SelectIsland);
DropdownIsland:OnChanged(function(Value)
	_G.SelectIsland = Value;
end);
Tabs.Teleport:AddButton({Title="Bay Đến Đảo",Description="",Callback=function()
	if (_G.SelectIsland == "WindMill") then
		Tween2(CFrame.new(979.79895019531, 16.516613006592, 1429.0466308594));
	elseif (_G.SelectIsland == "Marine") then
		Tween2(CFrame.new(-2566.4296875, 6.8556680679321, 2045.2561035156));
	elseif (_G.SelectIsland == "Middle Town") then
		Tween2(CFrame.new(-690.33081054688, 15.09425163269, 1582.2380371094));
	elseif (_G.SelectIsland == "Jungle") then
		Tween2(CFrame.new(-1612.7957763672, 36.852081298828, 149.12843322754));
	elseif (_G.SelectIsland == "Pirate Village") then
		Tween2(CFrame.new(-1181.3093261719, 4.7514905929565, 3803.5456542969));
	elseif (_G.SelectIsland == "Desert") then
		Tween2(CFrame.new(944.15789794922, 20.919729232788, 4373.3002929688));
	elseif (_G.SelectIsland == "Snow Island") then
		Tween2(CFrame.new(1347.8067626953, 104.66806030273, -1319.7370605469));
	elseif (_G.SelectIsland == "MarineFord") then
		Tween2(CFrame.new(-4914.8212890625, 50.963626861572, 4281.0278320313));
	elseif (_G.SelectIsland == "Colosseum") then
		Tween2(CFrame.new(-1427.6203613281, 7.2881078720093, -2792.7722167969));
	elseif (_G.SelectIsland == "Sky Island 1") then
		Tween2(CFrame.new(-4869.1025390625, 733.46051025391, -2667.0180664063));
	elseif (_G.SelectIsland == "Sky Island 2") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-4607.82275, 872.54248, -1667.55688));
	elseif (_G.SelectIsland == "Sky Island 3") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-7894.6176757813, 5547.1416015625, -380.29119873047));
	elseif (_G.SelectIsland == "Prison") then
		Tween2(CFrame.new(4875.330078125, 5.6519818305969, 734.85021972656));
	elseif (_G.SelectIsland == "Magma Village") then
		Tween2(CFrame.new(-5247.7163085938, 12.883934020996, 8504.96875));
	elseif (_G.SelectIsland == "Under Water Island") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(61163.8515625, 11.6796875, 1819.7841796875));
	elseif (_G.SelectIsland == "Fountain City") then
		Tween2(CFrame.new(5127.1284179688, 59.501365661621, 4105.4458007813));
	elseif (_G.SelectIsland == "Shank Room") then
		Tween2(CFrame.new(-1442.16553, 29.8788261, -28.3547478));
	elseif (_G.SelectIsland == "Mob Island") then
		Tween2(CFrame.new(-2850.20068, 7.39224768, 5354.99268));
	elseif (_G.SelectIsland == "The Cafe") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-281.93707275390625, 306.130615234375, 609.280029296875));
		wait();
		Tween2(CFrame.new(-380.47927856445, 77.220390319824, 255.82550048828));
	elseif (_G.SelectIsland == "Frist Spot") then
		Tween2(CFrame.new(-11.311455726624, 29.276733398438, 2771.5224609375));
	elseif (_G.SelectIsland == "Dark Area") then
		Tween2(CFrame.new(3780.0302734375, 22.652164459229, -3498.5859375));
	elseif (_G.SelectIsland == "Flamingo Mansion") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-281.93707275390625, 306.130615234375, 609.280029296875));
	elseif (_G.SelectIsland == "Flamingo Room") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(2284.912109375, 15.152034759521484, 905.48291015625));
	elseif (_G.SelectIsland == "Green Zone") then
		Tween2(CFrame.new(-2448.5300292969, 73.016105651855, -3210.6306152344));
	elseif (_G.SelectIsland == "Factory") then
		Tween2(CFrame.new(424.12698364258, 211.16171264648, -427.54049682617));
	elseif (_G.SelectIsland == "Colossuim") then
		Tween2(CFrame.new(-1503.6224365234, 219.7956237793, 1369.3101806641));
	elseif (_G.SelectIsland == "Zombie Island") then
		Tween2(CFrame.new(-5622.033203125, 492.19604492188, -781.78552246094));
	elseif (_G.SelectIsland == "Two Snow Mountain") then
		Tween2(CFrame.new(753.14288330078, 408.23559570313, -5274.6147460938));
	elseif (_G.SelectIsland == "Punk Hazard") then
		Tween2(CFrame.new(-6127.654296875, 15.951762199402, -5040.2861328125));
	elseif (_G.SelectIsland == "Cursed Ship") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(923.40197753906, 125.05712890625, 32885.875));
	elseif (_G.SelectIsland == "Ice Castle") then
		Tween2(CFrame.new(6148.4116210938, 294.38687133789, -6741.1166992188));
	elseif (_G.SelectIsland == "Forgotten Island") then
		Tween2(CFrame.new(-3032.7641601563, 317.89672851563, -10075.373046875));
	elseif (_G.SelectIsland == "Ussop Island") then
		Tween2(CFrame.new(4816.8618164063, 8.4599885940552, 2863.8195800781));
	elseif (_G.SelectIsland == "Mini Sky Island") then
		Tween2(CFrame.new(-288.74060058594, 49326.31640625, -35248.59375));
	elseif (_G.SelectIsland == "Great Tree") then
		Tween2(CFrame.new(2681.2736816406, 1682.8092041016, -7190.9853515625));
	elseif (_G.SelectIsland == "Castle On The Sea") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-5075.50927734375, 314.5155029296875, -3150.0224609375));
	elseif (_G.SelectIsland == "MiniSky") then
		Tween2(CFrame.new(-260.65557861328, 49325.8046875, -35253.5703125));
	elseif (_G.SelectIsland == "Port Town") then
		Tween2(CFrame.new(-290.7376708984375, 6.729952812194824, 5343.5537109375));
	elseif (_G.SelectIsland == "Hydra Island") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(5661.5322265625, 1013.0907592773438, -334.9649963378906));
	elseif (_G.SelectIsland == "Floating Turtle") then
		Tween2(CFrame.new(-13274.528320313, 531.82073974609, -7579.22265625));
	elseif (_G.SelectIsland == "Mansion") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-12468.5380859375, 375.0094299316406, -7554.62548828125));
	elseif (_G.SelectIsland == "Castle On The Sea") then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-5075.50927734375, 314.5155029296875, -3150.0224609375));
	elseif (_G.SelectIsland == "Haunted Castle") then
		Tween2(CFrame.new(-9515.3720703125, 164.00624084473, 5786.0610351562));
	elseif (_G.SelectIsland == "Ice Cream Island") then
		Tween2(CFrame.new(-902.56817626953, 79.93204498291, -10988.84765625));
	elseif (_G.SelectIsland == "Peanut Island") then
		Tween2(CFrame.new(-2062.7475585938, 50.473892211914, -10232.568359375));
	elseif (_G.SelectIsland == "Cake Island") then
		Tween2(CFrame.new(-1884.7747802734375, 19.327526092529297, -11666.8974609375));
	elseif (_G.SelectIsland == "Cocoa Island") then
		Tween2(CFrame.new(87.94276428222656, 73.55451202392578, -12319.46484375));
	elseif (_G.SelectIsland == "Candy Island") then
		Tween2(CFrame.new(-1014.4241943359375, 149.11068725585938, -14555.962890625));
	elseif (_G.SelectIsland == "Tiki Outpost") then
		Tween2(CFrame.new(-16542.447265625, 55.68632888793945, 1044.41650390625));
	end
end});
Tabs.Teleport:AddButton({Title="Dừng Bay",Description="",Callback=function()
	CancelTween();
end});
Tabs.Visual:AddButton({Title="Giả",Description="",Callback=function()
	local plr = game:GetService("Players").LocalPlayer;
	local Notification = require(game:GetService("ReplicatedStorage").Notification);
	local Data = plr:WaitForChild("Data");
	local EXPFunction = require(game.ReplicatedStorage:WaitForChild("EXPFunction"));
	local LevelUp = require(game:GetService("ReplicatedStorage").Effect.Container.LevelUp);
	local Sound = require(game:GetService("ReplicatedStorage").Util.Sound);
	local LevelUpSound = game:GetService("ReplicatedStorage").Util.Sound.Storage.Other:FindFirstChild("LevelUp_Proxy") or game:GetService("ReplicatedStorage").Util.Sound.Storage.Other:FindFirstChild("LevelUp");
	function v129(p15)
		local v130 = p15;
		while true do
			local v131, v132 = string.gsub(v130, "^(-?%d+)(%d%d%d)", "%1,%2");
			v130 = v131;
			if (v132 == 0) then
				break;
			end
		end
		return v130;
	end
	Notification.new("<Color=Yellow>QUEST COMPLETED!<Color=/>"):Display();
	Notification.new("Earned<Color=Yellow>9,999,999,999,999 Exp.<Color=/>(+None)"):Display();
	Notification.new("Earned<Color=Green>$9,999,999,999,999<Color=/>"):Display();
	plr.Data.Exp.Value = 999999999999;
	plr.Data.Beli.Value = plr.Data.Beli.Value + 999999999999;
	delay = 0;
	count = 0;
	while (plr.Data.Exp.Value - EXPFunction(Data.Level.Value)) > 0 do
		plr.Data.Exp.Value = plr.Data.Exp.Value - EXPFunction(Data.Level.Value);
		plr.Data.Level.Value = plr.Data.Level.Value + 1;
		plr.Data.Points.Value = plr.Data.Points.Value + 3;
		LevelUp({plr});
		Sound.Play(Sound, LevelUpSound.Value);
		Notification.new("<Color=Green>LEVEL UP!<Color=/>(" .. plr.Data.Level.Value .. ")"):Display();
		count = count + 1;
		if (count >= 5) then
			delay = tick();
			count = 0;
			wait();
		end
	end
end});
Tabs.Visual:AddInput("Input_Level", {Title="Cấp",Default="",Placeholder="Nhập",Numeric=false,Finished=false,Callback=function(value)
	game:GetService("Players")['LocalPlayer'].Data.Level.Value = tonumber(value);
end});
Tabs.Visual:AddInput("Input_EXP", {Title="Kinh Nghiệm",Default="",Placeholder="Nhập",Numeric=false,Finished=false,Callback=function(value)
	game:GetService("Players")['LocalPlayer'].Data.Exp.Value = tonumber(value);
end});
Tabs.Visual:AddInput("Input_Beli", {Title="Tiền",Default="",Placeholder="Nhập",Numeric=false,Finished=false,Callback=function(value)
	game:GetService("Players")['LocalPlayer'].Data.Beli.Value = tonumber(value);
end});
Tabs.Visual:AddInput("Input_Fragments", {Title="Điểm F",Default="",Placeholder="Nhập",Numeric=false,Finished=false,Callback=function(value)
	game:GetService("Players")['LocalPlayer'].Data.Fragments.Value = tonumber(value);
end});
local Remote_GetFruits = game.ReplicatedStorage:FindFirstChild("Remotes").CommF_:InvokeServer("GetFruits");
Table_DevilFruitSniper = {};
ShopDevilSell = {};
for i, v in next, Remote_GetFruits do
	table.insert(Table_DevilFruitSniper, v.Name);
	if v.OnSale then
		table.insert(ShopDevilSell, v.Name);
	end
end
_G.SelectFruit = "Dragon-Dragon";
_G.PermanentFruit = "Dragon-Dragon";
_G.AutoBuyFruitSniper = false;
_G.AutoSwitchPermanentFruit = false;
local DropdownFruit = Tabs.Fruit:AddDropdown("DropdownFruit", {Title="Chọn Trái",Description="",Values=Table_DevilFruitSniper,Multi=false,Default=1});
DropdownFruit:SetValue(_G.SelectFruit);
DropdownFruit:OnChanged(function(Value)
	_G.SelectFruit = Value;
end);
local ToggleFruit = Tabs.Fruit:AddToggle("ToggleFruit", {Title="Mua Trái Chọn",Description="",Default=false});
ToggleFruit:OnChanged(function(Value)
	if Value then
		_G.AutoBuyFruitSniper = true;
		pcall(function()
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("GetFruits");
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("PurchaseRawFruit", _G.SelectFruit, false);
		end);
		_G.AutoBuyFruitSniper = false;
	end
end);
Options.ToggleFruit:SetValue(false);
local DropdownPermanentFruit = Tabs.Fruit:AddDropdown("DropdownPermanentFruit", {Title="Chọn Trái Vĩnh Viễn",Description="",Values=Table_DevilFruitSniper,Multi=false,Default=1});
DropdownPermanentFruit:SetValue(_G.PermanentFruit);
DropdownPermanentFruit:OnChanged(function(Value)
	_G.PermanentFruit = Value;
end);
local TogglePermanentFruit = Tabs.Fruit:AddToggle("TogglePermanentFruit", {Title="Đổi Trái Vĩnh Viễn",Description="",Default=false});
TogglePermanentFruit:OnChanged(function(Value)
	if Value then
		_G.AutoSwitchPermanentFruit = true;
		pcall(function()
			local args = {[1]="SwitchFruit",[2]=_G.PermanentFruit};
			game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
		end);
		_G.AutoSwitchPermanentFruit = false;
	end
end);
Options.TogglePermanentFruit:SetValue(false);
local ToggleStore = Tabs.Fruit:AddToggle("ToggleStore", {Title="Lưu Trái",Description="",Default=false});
ToggleStore:OnChanged(function(Value)
	_G.AutoStoreFruit = Value;
end);
Options.ToggleStore:SetValue(false);
spawn(function()
	while task.wait() do
		if _G.AutoStoreFruit then
			pcall(function()
				if _G.AutoStoreFruit then
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Bomb Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Bomb Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Bomb-Bomb", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Bomb Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Spike Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spike Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Spike-Spike", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spike Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Chop Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Chop Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Chop-Chop", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Chop Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Spring Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spring Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Spring-Spring", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spring Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Rocket Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Kilo Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Rocket-Rocket", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Kilo Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Smoke Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Smoke Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Smoke-Smoke", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Smoke Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Spin Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spin Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Spin-Spin", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spin Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Flame Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Flame Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Flame-Flame", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Flame Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Falcon Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Falcon Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Falcon", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("alcon Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Ice Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Ice Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Ice-Ice", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Ice Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Sand Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Sand Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Sand-Sand", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Sand Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Dark Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Dark Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Dark-Dark", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Dark Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Ghost Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Revive Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Ghost-Ghost", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Revive Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Diamond Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Diamond Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Diamond-Diamond", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Diamond Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Light Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Light Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Light-Light", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Light Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Love Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Love Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Love-Love", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Love Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Rubber Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Rubber Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Rubber-Rubber", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Rubber Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Barrier Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Barrier Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Barrier-Barrier", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Barrier Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Magma Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Magma Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Magma-Magma", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Magma Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Portal Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Portal Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Door-Door", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Portal Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Quake Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Quake Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Quake-Quake", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Quake Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Buddha Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Buddha Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Buddha", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Buddha Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Spider Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spider Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Spider-Spider", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spider Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Bird: Phoenix Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Phoenix Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Phoenix", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Phoenix Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Rumble Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Rumble Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Rumble-Rumble", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Rumble Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Pain Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Pain Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Pain-Pain", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Pain Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Gravity Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Gravity Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Gravity-Gravity", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Gravity Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Dough Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Dough Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Dough-Dough", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Dough Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Shadow Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Shadow Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Shadow-Shadow", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Shadow Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Venom Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Venom Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Venom-Venom", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Venom Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Control Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Control Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Control-Control", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Control Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Spirit Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spirit Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Soul-Soul", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Spirit Fruit"));
					end
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Dragon Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Dragon Fruit")) then
						game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Dragon-Dragon", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Dragon Fruit"));
						if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Leopard Fruit") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Leopard Fruit")) then
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("StoreFruit", "Leopard-Leopard", game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Leopard Fruit"));
						end
					end
				end
			end);
		end
		wait();
	end
end);
local ToggleRandomFruit = Tabs.Fruit:AddToggle("ToggleRandomFruit", {Title="Random Trái",Description="",Default=false});
ToggleRandomFruit:OnChanged(function(Value)
	_G.Random_Auto = Value;
end);
Options.ToggleRandomFruit:SetValue(false);
spawn(function()
	pcall(function()
		while wait() do
			if _G.Random_Auto then
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Cousin", "Buy");
			end
		end
	end);
end);
local ToggleCollectTP = Tabs.Fruit:AddToggle("ToggleCollectTP", {Title="Bay Đến Trái",Description="",Default=false});
ToggleCollectTP:OnChanged(function(Value)
	_G.CollectFruitTP = Value;
end);
Options.ToggleCollectTP:SetValue(false);
spawn(function()
	while wait() do
		if _G.CollectFruitTP then
			for i, v in pairs(game.Workspace:GetChildren()) do
				if string.find(v.Name, "Fruit") then
					game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = v.Handle.CFrame;
				end
			end
		end
	end
end);
local ToggleCollect = Tabs.Fruit:AddToggle("ToggleCollect", {Title="Dịch Chuyển Đến Trái",Description="",Default=false});
ToggleCollect:OnChanged(function(Value)
	_G.Tweenfruit = Value;
end);
Options.ToggleCollect:SetValue(false);
spawn(function()
	while wait() do
		if _G.Tweenfruit then
			for i, v in pairs(game.Workspace:GetChildren()) do
				if string.find(v.Name, "Fruit") then
					Tween(v.Handle.CFrame);
				end
			end
		end
	end
end);
local Mastery = Tabs.Fruit:AddSection("Định Vị");
local ToggleEspPlayer = Tabs.Fruit:AddToggle("ToggleEspPlayer", {Title="Người Chơi",Description="",Default=false});
ToggleEspPlayer:OnChanged(function(Value)
	ESPPlayer = Value;
	UpdatePlayerChams();
end);
Options.ToggleEspPlayer:SetValue(false);
local ToggleEspFruit = Tabs.Fruit:AddToggle("ToggleEspFruit", {Title="Trái",Description="",Default=false});
ToggleEspFruit:OnChanged(function(Value)
	DevilFruitESP = Value;
	while DevilFruitESP do
		wait();
		UpdateDevilChams();
	end
end);
Options.ToggleEspFruit:SetValue(false);
local ToggleEspIsland = Tabs.Fruit:AddToggle("ToggleEspIsland", {Title="Đảo",Description="",Default=false});
ToggleEspIsland:OnChanged(function(Value)
	IslandESP = Value;
	while IslandESP do
		wait();
		UpdateIslandESP();
	end
end);
Options.ToggleEspIsland:SetValue(false);
local ToggleEspFlower = Tabs.Fruit:AddToggle("ToggleEspFlower", {Title="Hoa",Description="",Default=false});
ToggleEspFlower:OnChanged(function(Value)
	FlowerESP = Value;
	UpdateFlowerChams();
end);
Options.ToggleEspFlower:SetValue(false);
spawn(function()
	while wait() do
		if FlowerESP then
			UpdateFlowerChams();
		end
		if DevilFruitESP then
			UpdateDevilChams();
		end
		if ChestESP then
			UpdateChestChams();
		end
		if ESPPlayer then
			UpdatePlayerChams();
		end
		if RealFruitESP then
			UpdateRealFruitChams();
		end
	end
end);
local ToggleEspRealFruit = Tabs.Fruit:AddToggle("ToggleEspRealFruit", {Title="Trái Dứa Khớm Táo",Description="",Default=false});
ToggleEspRealFruit:OnChanged(function(Value)
	RealFruitEsp = Value;
	while RealFruitEsp do
		wait();
		UpdateRealFruitEsp();
	end
end);
Options.ToggleEspRealFruit:SetValue(false);
function UpdateRealFruitEsp()
	for _, v in pairs(game.Workspace.AppleSpawner:GetChildren()) do
		if v:IsA("Tool") then
			if RealFruitEsp then
				if not v.Handle:FindFirstChild("NameEsp" .. Number) then
					local bill = Instance.new("BillboardGui", v.Handle);
					bill.Name = "NameEsp" .. Number;
					bill.ExtentsOffset = Vector3.new(0, 1, 0);
					bill.Size = UDim2.new(1, 200, 1, 30);
					bill.Adornee = v.Handle;
					bill.AlwaysOnTop = true;
					local name = Instance.new("TextLabel", bill);
					name.Font = Enum.Font.GothamSemibold;
					name.FontSize = "Size14";
					name.TextWrapped = true;
					name.Size = UDim2.new(1, 0, 1, 0);
					name.TextYAlignment = "Top";
					name.BackgroundTransparency = 1;
					name.TextStrokeTransparency = 0.5;
					name.TextColor3 = Color3.fromRGB(255, 0, 0);
					name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				else
					v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end
	end
	for _, v in pairs(game.Workspace.PineappleSpawner:GetChildren()) do
		if v:IsA("Tool") then
			if RealFruitEsp then
				if not v.Handle:FindFirstChild("NameEsp" .. Number) then
					local bill = Instance.new("BillboardGui", v.Handle);
					bill.Name = "NameEsp" .. Number;
					bill.ExtentsOffset = Vector3.new(0, 1, 0);
					bill.Size = UDim2.new(1, 200, 1, 30);
					bill.Adornee = v.Handle;
					bill.AlwaysOnTop = true;
					local name = Instance.new("TextLabel", bill);
					name.Font = Enum.Font.GothamSemibold;
					name.FontSize = "Size14";
					name.TextWrapped = true;
					name.Size = UDim2.new(1, 0, 1, 0);
					name.TextYAlignment = "Top";
					name.BackgroundTransparency = 1;
					name.TextStrokeTransparency = 0.5;
					name.TextColor3 = Color3.fromRGB(255, 174, 0);
					name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				else
					v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end
	end
	for _, v in pairs(game.Workspace.BananaSpawner:GetChildren()) do
		if v:IsA("Tool") then
			if RealFruitEsp then
				if not v.Handle:FindFirstChild("NameEsp" .. Number) then
					local bill = Instance.new("BillboardGui", v.Handle);
					bill.Name = "NameEsp" .. Number;
					bill.ExtentsOffset = Vector3.new(0, 1, 0);
					bill.Size = UDim2.new(1, 200, 1, 30);
					bill.Adornee = v.Handle;
					bill.AlwaysOnTop = true;
					local name = Instance.new("TextLabel", bill);
					name.Font = Enum.Font.GothamSemibold;
					name.FontSize = "Size14";
					name.TextWrapped = true;
					name.Size = UDim2.new(1, 0, 1, 0);
					name.TextYAlignment = "Top";
					name.BackgroundTransparency = 1;
					name.TextStrokeTransparency = 0.5;
					name.TextColor3 = Color3.fromRGB(251, 255, 0);
					name.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				else
					v.Handle["NameEsp" .. Number].TextLabel.Text = v.Name .. " " .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Handle.Position).Magnitude / 3) .. " Distance";
				end
			elseif v.Handle:FindFirstChild("NameEsp" .. Number) then
				v.Handle:FindFirstChild("NameEsp" .. Number):Destroy();
			end
		end
	end
end
local ToggleIslandMirageEsp = Tabs.Fruit:AddToggle("ToggleIslandMirageEsp", {Title="Đảo Bí Ẩn",Description="",Default=false});
ToggleIslandMirageEsp:OnChanged(function(Value)
	IslandMirageEsp = Value;
	while IslandMirageEsp do
		wait();
		UpdateIslandMirageEsp();
	end
end);
Options.ToggleIslandMirageEsp:SetValue(false);
function isnil(thing)
	return thing == nil;
end
local function round(n)
	return math.floor(tonumber(n) + 0.5);
end
Number = math.random(1, 1000000);
function UpdateIslandMirageEsp()
	for _, v in pairs(game:GetService("Workspace")['_WorldOrigin'].Locations:GetChildren()) do
		pcall(function()
			if MirageIslandESP then
				if (v.Name == "Mirage Island") then
					if not v:FindFirstChild("NameEsp") then
						local bill = Instance.new("BillboardGui", v);
						bill.Name = "NameEsp";
						bill.ExtentsOffset = Vector3.new(0, 1, 0);
						bill.Size = UDim2.new(1, 200, 1, 30);
						bill.Adornee = v;
						bill.AlwaysOnTop = true;
						local name = Instance.new("TextLabel", bill);
						name.Font = Enum.Font.Code;
						name.FontSize = Enum.FontSize.Size14;
						name.TextWrapped = true;
						name.Size = UDim2.new(1, 0, 1, 0);
						name.TextYAlignment = Enum.TextYAlignment.Top;
						name.BackgroundTransparency = 1;
						name.TextStrokeTransparency = 0.5;
						name.TextColor3 = Color3.fromRGB(80, 245, 245);
					else
						v['NameEsp'].TextLabel.Text = v.Name .. " \n" .. round((game:GetService("Players").LocalPlayer.Character.Head.Position - v.Position).Magnitude / 3) .. " M";
					end
				end
			elseif v:FindFirstChild("NameEsp") then
				v:FindFirstChild("NameEsp"):Destroy();
			end
		end);
	end
end
local Chips = {"Flame","Ice","Quake","Light","Dark","Spider","Rumble","Magma","Buddha","Sand","Phoenix","Dough"};
local DropdownRaid = Tabs.Raid:AddDropdown("DropdownRaid", {Title="Chọn Chip",Description="",Values=Chips,Multi=false,Default=1});
DropdownRaid:SetValue(SelectChip);
DropdownRaid:OnChanged(function(Value)
	SelectChip = Value;
end);
local ToggleBuy = Tabs.Raid:AddToggle("ToggleBuy", {Title="Mua Chip",Description="",Default=false});
ToggleBuy:OnChanged(function(Value)
	_G.Auto_Buy_Chips_Dungeon = Value;
end);
Options.ToggleBuy:SetValue(false);
spawn(function()
	while wait() do
		if _G.Auto_Buy_Chips_Dungeon then
			pcall(function()
				local args = {[1]="RaidsNpc",[2]="Select",[3]=SelectChip};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
			end);
		end
	end
end);
local ToggleStart = Tabs.Raid:AddToggle("ToggleStart", {Title="Bắt Đầu Raid",Description="",Default=false});
ToggleStart:OnChanged(function(Value)
	_G.Auto_StartRaid = Value;
end);
Options.ToggleStart:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.Auto_StartRaid then
				if (game:GetService("Players")['LocalPlayer'].PlayerGui.Main.Timer.Visible == false) then
					if (not game:GetService("Workspace")['_WorldOrigin'].Locations:FindFirstChild("Island 1") and (game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Special Microchip") or game:GetService("Players").LocalPlayer.Character:FindFirstChild("Special Microchip"))) then
						if Sea2 then
							Tween2(CFrame.new(-6438.73535, 250.645355, -4501.50684));
							local args = {[1]="SetSpawnPoint"};
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
							fireclickdetector(game:GetService("Workspace").Map.CircleIsland.RaidSummon2.Button.Main.ClickDetector);
						elseif Sea3 then
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-5075.50927734375, 314.5155029296875, -3150.0224609375));
							Tween2(CFrame.new(-5017.40869, 314.844055, -2823.0127, -0.925743818, 4.482175e-8, -0.378151238, 4.5550315e-9, 1, 1.0737756e-7, 0.378151238, 9.768162e-8, -0.925743818));
							local args = {[1]="SetSpawnPoint"};
							game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
							fireclickdetector(game:GetService("Workspace").Map["Boat Castle"].RaidSummon2.Button.Main.ClickDetector);
						end
					end
				end
			end
		end);
	end
end);
local ToggleNextIsland = Tabs.Raid:AddToggle("ToggleNextIsland", {Title="Đấm Quái Raid+Bay Đến Đảo",Description="",Default=false});
ToggleNextIsland:OnChanged(function(Value)
	AutoNextIsland = Value;
	if not Value then
		_G.AutoNear = false;
	end
end);
Options.ToggleNextIsland:SetValue(false);
spawn(function()
	local visitedIslands = {};
	while task.wait() do
		if AutoNextIsland then
			pcall(function()
				local character = game.Players.LocalPlayer.Character;
				if (character and character:FindFirstChild("HumanoidRootPart")) then
					local locations = game:GetService("Workspace")['_WorldOrigin'].Locations;
					local pos = character.HumanoidRootPart.Position;
					if (((pos - Vector3.new(-6438.73535, 250.645355, -4501.50684)).Magnitude < 1) or ((pos - Vector3.new(-5017.40869, 314.844055, -2823.0127)).Magnitude < 1)) then
						visitedIslands = {};
					end
					if locations:FindFirstChild("Island 1") then
						_G.AutoNear = true;
					end
					if (locations:FindFirstChild("Island 2") and not visitedIslands["Island 2"]) then
						Tween(locations:FindFirstChild("Island 2").CFrame);
						visitedIslands["Island 2"] = true;
						AutoNextIsland = false;
						wait();
						AutoNextIsland = true;
					elseif (locations:FindFirstChild("Island 3") and not visitedIslands["Island 3"]) then
						Tween(locations:FindFirstChild("Island 3").CFrame);
						visitedIslands["Island 3"] = true;
						AutoNextIsland = false;
						wait();
						AutoNextIsland = true;
					elseif (locations:FindFirstChild("Island 4") and not visitedIslands["Island 4"]) then
						Tween(locations:FindFirstChild("Island 4").CFrame);
						visitedIslands["Island 4"] = true;
						AutoNextIsland = false;
						wait();
						AutoNextIsland = true;
					elseif (locations:FindFirstChild("Island 5") and not visitedIslands["Island 5"]) then
						Tween(locations:FindFirstChild("Island 5").CFrame);
						visitedIslands["Island 5"] = true;
						AutoNextIsland = false;
						wait();
						AutoNextIsland = true;
					end
				end
			end);
		end
	end
end);
local ToggleAwake = Tabs.Raid:AddToggle("ToggleAwake", {Title="Thức Tỉnh",Description="",Default=false});
ToggleAwake:OnChanged(function(Value)
	AutoAwakenAbilities = Value;
end);
Options.ToggleAwake:SetValue(false);
spawn(function()
	while task.wait() do
		if AutoAwakenAbilities then
			pcall(function()
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Awakener", "Awaken");
			end);
		end
	end
end);
local ToggleGetFruit = Tabs.Raid:AddToggle("ToggleGetFruit", {Title="Lấy Trái Dưới 1 Triệu",Description="",Default=false});
ToggleGetFruit:OnChanged(function(Value)
	_G.Autofruit = Value;
end);
spawn(function()
	while wait() do
		pcall(function()
			if _G.Autofruit then
				local args = {[1]="LoadFruit",[2]="Rocket-Rocket"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Spin-Spin"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Chop-Chop"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Spring-Spring"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Bomb-Bomb"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Smoke-Smoke"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Spike-Spike"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Flame-Flame"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Falcon-Falcon"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Ice-Ice"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Sand-Sand"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Dark-Dark"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Ghost-Ghost"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Diamond-Diamond"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Light-Light"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Rubber-Rubber"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
				local args = {[1]="LoadFruit",[2]="Barrier-Barrier"};
				game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
			end
		end);
	end
end);
if Sea2 then
	Tabs.Raid:AddButton({Title="Bay Đến Chỗ Tập Kích",Description="",Callback=function()
		Tween2(CFrame.new(-6438.73535, 250.645355, -4501.50684));
	end});
elseif Sea3 then
	Tabs.Raid:AddButton({Title="Bay Đến Chỗ Tập Kích",Description="",Callback=function()
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(-5075.50927734375, 314.5155029296875, -3150.0224609375));
		Tween2(CFrame.new(-5017.40869, 314.844055, -2823.0127, -0.925743818, 4.482175e-8, -0.378151238, 4.5550315e-9, 1, 1.0737756e-7, 0.378151238, 9.768162e-8, -0.925743818));
	end});
end
local Mastery = Tabs.Raid:AddSection("Tập Kích Law");
local ToggleLaw = Tabs.Raid:AddToggle("ToggleLaw", {Title="Mua Chip Và Đấm Law",Description="",Default=false});
ToggleLaw:OnChanged(function(Value)
	Auto_Law = Value;
end);
Options.ToggleLaw:SetValue(false);
spawn(function()
	pcall(function()
		while wait() do
			if Auto_Law then
				if (not game:GetService("Players").LocalPlayer.Character:FindFirstChild("Microchip") and not game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Microchip") and not game:GetService("Workspace").Enemies:FindFirstChild("Order") and not game:GetService("ReplicatedStorage"):FindFirstChild("Order")) then
					wait();
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BlackbeardReward", "Microchip", "1");
					game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BlackbeardReward", "Microchip", "2");
				end
			end
		end
	end);
end);
spawn(function()
	pcall(function()
		while wait() do
			if Auto_Law then
				if (not game:GetService("Workspace").Enemies:FindFirstChild("Order") and not game:GetService("ReplicatedStorage"):FindFirstChild("Order")) then
					if (game:GetService("Players").LocalPlayer.Character:FindFirstChild("Microchip") or game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Microchip")) then
						fireclickdetector(game:GetService("Workspace").Map.CircleIsland.RaidSummon.Button.Main.ClickDetector);
					end
				end
				if (game:GetService("ReplicatedStorage"):FindFirstChild("Order") or game:GetService("Workspace").Enemies:FindFirstChild("Order")) then
					if game:GetService("Workspace").Enemies:FindFirstChild("Order") then
						for i, v in pairs(game:GetService("Workspace").Enemies:GetChildren()) do
							if (v.Name == "Order") then
								repeat
									wait(_G.Fast_Delay);
									AttackNoCoolDown();
									AutoHaki();
									EquipTool(SelectWeapon);
									Tween(v.HumanoidRootPart.CFrame * Pos);
									v.HumanoidRootPart.CanCollide = false;
									v.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
								until not v.Parent or (v.Humanoid.Health <= 0) or (Auto_Law == false) 
							end
						end
					elseif game:GetService("ReplicatedStorage"):FindFirstChild("Order") then
						Tween(CFrame.new(-6217.2021484375, 28.047645568848, -5053.1357421875));
					end
				end
			end
		end
	end);
end);
Tabs.Race:AddButton({Title="Đền Thời Gian",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(28286.35546875, 14895.3017578125, 102.62469482421875));
end});
Tabs.Race:AddButton({Title="Cần Gạt",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(28286.35546875, 14895.3017578125, 102.62469482421875));
	Tween2(CFrame.new(28575.181640625, 14936.6279296875, 72.31636810302734));
end});
Tabs.Race:AddButton({Title="Chỗ Mua Gear",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(28286.35546875, 14895.3017578125, 102.62469482421875));
	Tween2(CFrame.new(28981.552734375, 14888.4267578125, -120.245849609375));
end});
local Mastery = Tabs.Race:AddSection("Tộc");
Tabs.Race:AddButton({Title="Cửa Tộc",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(28286.35546875, 14895.3017578125, 102.62469482421875));
	if (game:GetService("Players").LocalPlayer.Data.Race.Value == "Human") then
		Tween2(CFrame.new(29221.822265625, 14890.9755859375, -205.99114990234375));
	elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Skypiea") then
		Tween2(CFrame.new(28960.158203125, 14919.6240234375, 235.03948974609375));
	elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Fishman") then
		Tween2(CFrame.new(28231.17578125, 14890.9755859375, -211.64173889160156));
	elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Cyborg") then
		Tween2(CFrame.new(28502.681640625, 14895.9755859375, -423.7279357910156));
	elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Ghoul") then
		Tween2(CFrame.new(28674.244140625, 14890.6767578125, 445.4310607910156));
	elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Mink") then
		Tween2(CFrame.new(29012.341796875, 14890.9755859375, -380.1492614746094));
	end
end});
local ToggleHumanandghoul = Tabs.Race:AddToggle("ToggleHumanandghoul", {Title="Hoàn Thành Ải [Human/Ghoul]",Description="",Default=false});
ToggleHumanandghoul:OnChanged(function(Value)
	KillAura = Value;
end);
Options.ToggleHumanandghoul:SetValue(false);
local ToggleAutotrial = Tabs.Race:AddToggle("ToggleAutotrial", {Title="Hoàn Thành Ải",Description="",Default=false});
ToggleAutotrial:OnChanged(function(Value)
	_G.AutoQuestRace = Value;
end);
Options.ToggleAutotrial:SetValue(false);
spawn(function()
	pcall(function()
		while wait() do
			if _G.AutoQuestRace then
				if (game:GetService("Players").LocalPlayer.Data.Race.Value == "Human") then
					for i, v in pairs(game.Workspace.Enemies:GetDescendants()) do
						if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
							pcall(function()
								repeat
									wait();
									v.Humanoid.Health = 0;
									v.HumanoidRootPart.CanCollide = false;
									sethiddenproperty(game.Players.LocalPlayer, "SimulationRadius", math.huge);
								until not _G.AutoQuestRace or not v.Parent or (v.Humanoid.Health <= 0) 
							end);
						end
					end
				elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Skypiea") then
					for i, v in pairs(game:GetService("Workspace").Map.SkyTrial.Model:GetDescendants()) do
						if (v.Name == "snowisland_Cylinder.081") then
							BTPZ(v.CFrame * CFrame.new(0, 0, 0));
						end
					end
				elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Fishman") then
					for i, v in pairs(game:GetService("Workspace").SeaBeasts.SeaBeast1:GetDescendants()) do
						if (v.Name == "HumanoidRootPart") then
							Tween(v.CFrame * Pos);
							for i, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
								if v:IsA("Tool") then
									if (v.ToolTip == "Melee") then
										game.Players.LocalPlayer.Character.Humanoid:EquipTool(v);
									end
								end
							end
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait(0.2);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait(0.2);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							for i, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
								if v:IsA("Tool") then
									if (v.ToolTip == "Blox Fruit") then
										game.Players.LocalPlayer.Character.Humanoid:EquipTool(v);
									end
								end
							end
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait(0.2);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait(0.2);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait();
							for i, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
								if v:IsA("Tool") then
									if (v.ToolTip == "Sword") then
										game.Players.LocalPlayer.Character.Humanoid:EquipTool(v);
									end
								end
							end
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait(0.2);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait(0.2);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait();
							for i, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
								if v:IsA("Tool") then
									if (v.ToolTip == "Gun") then
										game.Players.LocalPlayer.Character.Humanoid:EquipTool(v);
									end
								end
							end
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 122, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait(0.2);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 120, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							wait(0.2);
							game:GetService("VirtualInputManager"):SendKeyEvent(true, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, 99, false, game.Players.LocalPlayer.Character.HumanoidRootPart);
						end
					end
				elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Cyborg") then
					Tween(CFrame.new(28654, 14898.7832, -30, 1, 0, 0, 0, 1, 0, 0, 0, 1));
				elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Ghoul") then
					for i, v in pairs(game.Workspace.Enemies:GetDescendants()) do
						if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
							pcall(function()
								repeat
									wait();
									v.Humanoid.Health = 0;
									v.HumanoidRootPart.CanCollide = false;
									sethiddenproperty(game.Players.LocalPlayer, "SimulationRadius", math.huge);
								until not _G.AutoQuestRace or not v.Parent or (v.Humanoid.Health <= 0) 
							end);
						end
					end
				elseif (game:GetService("Players").LocalPlayer.Data.Race.Value == "Mink") then
					for i, v in pairs(game:GetService("Workspace"):GetDescendants()) do
						if (v.Name == "StartPoint") then
							Tween(v.CFrame * CFrame.new(0, 10, 0));
						end
					end
				end
			end
		end
	end);
end);
local ToggleKillTrial = Tabs.Race:AddToggle("ToggleKillTrial", {Title="Đấm Người Chơi Trong Trial",Description="",Default=false});
ToggleKillTrial:OnChanged(function(Value)
	_G.AutoKillTrial = Value;
end);
Options.ToggleKillTrial:SetValue(false);
spawn(function()
	while wait() do
		pcall(function()
			if _G.AutoKillTrial then
				for _, v in pairs(game:GetService("Players"):GetChildren()) do
					if (v.Name and (v.Name ~= game.Players.LocalPlayer.Name) and ((v.Character.HumanoidRootPart.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 100)) then
						if (v.Character.Humanoid.Health > 0) then
							repeat
								wait(_G.Fast_Delay);
								EquipTool(SelectWeapon);
								AutoHaki();
								Tween(v.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 5));
								v.Character.HumanoidRootPart.CanCollide = false;
								v.Character.HumanoidRootPart.Size = Vector3.new(60, 60, 60);
								AttackNoCoolDown();
							until not _G.AutoKillTrial or not v.Parent or (v.Character.Humanoid.Health <= 0) 
						end
					end
				end
			end
		end);
	end
end);
local Mastery = Tabs.Race:AddSection("Huấn Luyện");
local ToggleFarmRace = Tabs.Race:AddToggle("ToggleFarmRace", {Title="Cày Luyện Tộc",Description="",Default=false});
local AutoFarmRace = false;
ToggleFarmRace:OnChanged(function(Value)
	AutoFarmRace = Value;
end);
Options.ToggleFarmRace:SetValue(false);
spawn(function()
	while wait() do
		if AutoFarmRace then
			pcall(function()
				if game.Players.LocalPlayer.Character:FindFirstChild("RaceTransformed") then
					if (game.Players.LocalPlayer.Character.RaceTransformed.Value == true) then
						_G.AutoBoneNoQuest = false;
						Tween(CFrame.new(-9698.4736328125, 445.09442138671875, 6545.8525390625));
					elseif (game.Players.LocalPlayer.Character.RaceTransformed.Value == false) then
						_G.AutoBoneNoQuest = true;
						game:GetService("VirtualInputManager"):SendKeyEvent(true, "Y", false, game);
						wait();
						game:GetService("VirtualInputManager"):SendKeyEvent(false, "Y", false, game);
					end
				end
			end);
		else
			_G.AutoBoneNoQuest = false;
		end
	end
end);
local ToggleUpgrade = Tabs.Race:AddToggle("ToggleUpgrade", {Title="Mua Gear",Description="",Default=false});
ToggleUpgrade:OnChanged(function(Value)
	_G.AutoUpgrade = Value;
	if _G.AutoUpgrade then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("UpgradeRace", "Buy");
	end
end);
Options.ToggleUpgrade:SetValue(false);
local Mastery = Tabs.Shop:AddSection("Khả Năng");
Tabs.Shop:AddButton({Title="Nhảy",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyHaki", "Geppo");
end});
Tabs.Shop:AddButton({Title="Haki Đấm",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyHaki", "Buso");
end});
Tabs.Shop:AddButton({Title="Dịch Chuyển",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyHaki", "Soru");
end});
Tabs.Shop:AddButton({Title="Haki Quan Sát",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("KenTalk", "Buy");
end});
local Mastery = Tabs.Shop:AddSection("Kiếm");
Tabs.Shop:AddButton({Title="Cutlass",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyItem", "Cutlass");
end});
Tabs.Shop:AddButton({Title="Katana",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyItem", "Katana");
end});
Tabs.Shop:AddButton({Title="Iron Mace",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyItem", "Iron Mace");
end});
Tabs.Shop:AddButton({Title="Duel Katana",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyItem", "Duel Katana");
end});
Tabs.Shop:AddButton({Title="Triple Katana",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyItem", "Triple Katana");
end});
Tabs.Shop:AddButton({Title="Pipe",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyItem", "Pipe");
end});
Tabs.Shop:AddButton({Title="Dual-Headed Blade",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyItem", "Dual-Headed Blade");
end});
Tabs.Shop:AddButton({Title="Bisento",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyItem", "Bisento");
end});
Tabs.Shop:AddButton({Title="Soul Cane",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyItem", "Soul Cane");
end});
Tabs.Shop:AddButton({Title="Pole V2",Description="",Callback=function()
	game.ReplicatedStorage.Remotes.CommF_:InvokeServer("ThunderGodTalk");
end});
local Mastery = Tabs.Shop:AddSection("Võ");
Tabs.Shop:AddButton({Title="Black Leg",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyBlackLeg");
end});
Tabs.Shop:AddButton({Title="Electro",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyElectro");
end});
Tabs.Shop:AddButton({Title="Fishman Karate",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyFishmanKarate");
end});
Tabs.Shop:AddButton({Title="Dragon Claw",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BlackbeardReward", "DragonClaw", "1");
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BlackbeardReward", "DragonClaw", "2");
end});
Tabs.Shop:AddButton({Title="Superhuman",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuySuperhuman");
end});
Tabs.Shop:AddButton({Title="Death Step",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyDeathStep");
end});
Tabs.Shop:AddButton({Title="Sharkman Karate",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuySharkmanKarate", true);
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuySharkmanKarate");
end});
Tabs.Shop:AddButton({Title="Electric Claw",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyElectricClaw");
end});
Tabs.Shop:AddButton({Title="Dragon Talon",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyDragonTalon");
end});
Tabs.Shop:AddButton({Title="Godhuman",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuyGodhuman");
end});
Tabs.Shop:AddButton({Title="Sanguine Art",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuySanguineArt");
end});
local Mastery = Tabs.Shop:AddSection("Khác");
Tabs.Shop:AddButton({Title="Đổi Chỉ Số",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BlackbeardReward", "Refund", "1");
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BlackbeardReward", "Refund", "2");
end});
Tabs.Shop:AddButton({Title="Đổi Tộc",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BlackbeardReward", "Reroll", "1");
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BlackbeardReward", "Reroll", "2");
end});
Tabs.Shop:AddButton({Title="Đổi Tộc Ghoul",Description="",Callback=function()
	local args = {[1]="Ectoplasm",[2]="Change",[3]=4};
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
end});
Tabs.Shop:AddButton({Title="Đổi Tộc Cyborg",Description="",Callback=function()
	local args = {[1]="CyborgTrainer",[2]="Buy"};
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
end});
Tabs.Shop:AddButton({Title="Đổi Tộc Draco",Description="Chỉ Ở Biển 3",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(5661.5322265625, 1013.0907592773438, -334.9649963378906));
	Tween2(CFrame.new(5814.42724609375, 1208.3267822265625, 884.5785522460938));
	local targetPosition = Vector3.new(5814.42724609375, 1208.3267822265625, 884.5785522460938);
	local player = game.Players.LocalPlayer;
	local character = player.Character or player.CharacterAdded:Wait();
	repeat
		wait();
	until (character.HumanoidRootPart.Position - targetPosition).Magnitude < 1 
	local args = {[1]={NPC="Dragon Wizard",Command="DragonRace"}};
	game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/InteractDragonQuest"):InvokeServer(unpack(args));
end});
Tabs.Misc:AddButton({Title="Tham Gia Máy Chủ Lại",Description="",Callback=function()
	game:GetService("TeleportService"):Teleport(game.PlaceId, game:GetService("Players").LocalPlayer);
end});
Tabs.Misc:AddButton({Title="Đổi Máy Chủ",Description="",Callback=function()
	Hop();
end});
function Hop()
	local PlaceID = game.PlaceId;
	local AllIDs = {};
	local foundAnything = "";
	local actualHour = os.date("!*t").hour;
	local Deleted = false;
	function TPReturner()
		local Site;
		if (foundAnything == "") then
			Site = game.HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100"));
		else
			Site = game.HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100&cursor=" .. foundAnything));
		end
		local ID = "";
		if (Site.nextPageCursor and (Site.nextPageCursor ~= "null") and (Site.nextPageCursor ~= nil)) then
			foundAnything = Site.nextPageCursor;
		end
		local num = 0;
		for i, v in pairs(Site.data) do
			local Possible = true;
			ID = tostring(v.id);
			if (tonumber(v.maxPlayers) > tonumber(v.playing)) then
				for _, Existing in pairs(AllIDs) do
					if (num ~= 0) then
						if (ID == tostring(Existing)) then
							Possible = false;
						end
					elseif (tonumber(actualHour) ~= tonumber(Existing)) then
						local delFile = pcall(function()
							AllIDs = {};
							table.insert(AllIDs, actualHour);
						end);
					end
					num = num + 1;
				end
				if (Possible == true) then
					table.insert(AllIDs, ID);
					wait();
					pcall(function()
						wait();
						game:GetService("TeleportService"):TeleportToPlaceInstance(PlaceID, ID, game.Players.LocalPlayer);
					end);
					wait();
				end
			end
		end
	end
	function Teleport()
		while wait() do
			pcall(function()
				TPReturner();
				if (foundAnything ~= "") then
					TPReturner();
				end
			end);
		end
	end
	Teleport();
end
local Mastery = Tabs.Misc:AddSection("Đội");
Tabs.Misc:AddButton({Title="Hải Tặc",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("SetTeam", "Pirates");
end});
Tabs.Misc:AddButton({Title="Hải Quân",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("SetTeam", "Marines");
end});
local Mastery = Tabs.Misc:AddSection("Kinh Nghiệm");
local codes = {"KITT_RESET","Sub2UncleKizaru","SUB2GAMERROBOT_RESET1","Sub2Fer999","Enyu_is_Pro","JCWK","StarcodeHEO","MagicBus","KittGaming","Sub2CaptainMaui","Sub2OfficalNoobie","TheGreatAce","Sub2NoobMaster123","Sub2Daigrock","Axiore","StrawHatMaine","TantaiGaming","Bluxxy","SUB2GAMERROBOT_EXP1","Chandler","NOMOREHACK","BANEXPLOIT","WildDares","BossBuild","GetPranked","EARN_FRUITS","FIGHT4FRUIT","NOEXPLOITER","NOOB2ADMIN","CODESLIDE","ADMINHACKED","ADMINDARES","fruitconcepts","krazydares","TRIPLEABUSE","SEATROLLING","24NOADMIN","REWARDFUN","NEWTROLL","fudd10_v2","Fudd10","Bignews","SECRET_ADMIN"};
Tabs.Misc:AddButton({Title="Nhập Hết",Description="",Callback=function()
	for _, code in ipairs(codes) do
		RedeemCode(code);
	end
end});
function RedeemCode(Code)
	game:GetService("ReplicatedStorage").Remotes.Redeem:InvokeServer(Code);
end
local Mastery = Tabs.Misc:AddSection("Danh Hiệu");
Tabs.Misc:AddButton({Title="Danh Hiệu",Description="",Callback=function()
	local args = {[1]="getTitles"};
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
	game.Players.localPlayer.PlayerGui.Main.Titles.Visible = true;
end});
local Mastery = Tabs.Misc:AddSection("Thức Tỉnh");
Tabs.Misc:AddButton({Title="Thức Tỉnh",Description="",Callback=function()
	game:GetService("Players").LocalPlayer.PlayerGui.Main.AwakeningToggler.Visible = true;
end});
local Mastery = Tabs.Misc:AddSection("Khác");
local ToggleRejoin = Tabs.Misc:AddToggle("ToggleRejoin", {Title="Tham Gia Máy Chủ Lại",Description="",Default=true});
ToggleRejoin:OnChanged(function(Value)
	_G.AutoRejoin = Value;
end);
Options.ToggleRejoin:SetValue(true);
spawn(function()
	while wait() do
		if _G.AutoRejoin then
			getgenv().rejoin = game:GetService("CoreGui").RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
				if ((child.Name == "ErrorPrompt") and child:FindFirstChild("MessageArea") and child.MessageArea:FindFirstChild("ErrorFrame")) then
					game:GetService("TeleportService"):Teleport(game.PlaceId);
				end
			end);
		end
	end
end);
local Mastery = Tabs.Misc:AddSection("Sương");
local function NoFog()
	local lighting = game:GetService("Lighting");
	if lighting:FindFirstChild("BaseAtmosphere") then
		lighting.BaseAtmosphere:Destroy();
	end
	if lighting:FindFirstChild("SeaTerrorCC") then
		lighting.SeaTerrorCC:Destroy();
	end
	if lighting:FindFirstChild("LightingLayers") then
		if lighting.LightingLayers:FindFirstChild("Atmosphere") then
			lighting.LightingLayers.Atmosphere:Destroy();
		end
		wait();
		if lighting.LightingLayers:FindFirstChild("DarkFog") then
			lighting.LightingLayers.DarkFog:Destroy();
		end
	end
	lighting.FogEnd = 100000;
end
Tabs.Misc:AddButton({Title="Xóa Sương Mù",Description="",Callback=function()
	NoFog();
end});
local ToggleAntiBand = Tabs.Misc:AddToggle("ToggleAntiBand", {Title="Chống Band",Description="",Default=true});
ToggleAntiBand:OnChanged(function(Value)
	_G.AntiBand = Value;
end);
local dangerousIDs = {17884881,120173604,912348};
spawn(function()
	while wait() do
		if _G.AntiBand then
			for _, player in pairs(game:GetService("Players"):GetPlayers()) do
				if table.find(dangerousIDs, player.UserId) then
					Hop();
				end
			end
		end
	end
end);
local Mastery = Tabs.Sea:AddSection("Leviathan");
Tabs.Sea:AddButton({Title="Mua Chip Leviathan",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("InfoLeviathan", "2");
end});
local ToggleTPFrozenDimension = Tabs.Sea:AddToggle("ToggleTPFrozenDimension", {Title="Bay Đến Đảo Leviathan",Description="",Default=false});
ToggleTPFrozenDimension:OnChanged(function(Value)
	_G.TweenToFrozenDimension = Value;
end);
ToggleTPFrozenDimension:SetValue(false);
spawn(function()
	local island;
	while not island do
		island = game:GetService("Workspace").Map:FindFirstChild("FrozenDimension");
		wait();
	end
	while wait() do
		if _G.TweenToFrozenDimension then
			if island then
				Tween(island.CFrame);
			end
		end
	end
end);
if Sea3 then
	local BribeLeviathan = Tabs.Sea:AddParagraph({Title="Trạng Thái Chip Leviathan",Content=""});
	spawn(function()
		pcall(function()
			while wait() do
				local bribeStatus = game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("InfoLeviathan", "1");
				if (bribeStatus == 5) then
					BribeLeviathan:SetDesc("Leviathan Is Out There");
				elseif (bribeStatus == 0) then
					BribeLeviathan:SetDesc("I Don't Know");
				else
					BribeLeviathan:SetDesc("Mua: " .. tostring(bribeStatus));
				end
			end
		end);
	end);
end
local Blaze = Tabs.Sea:AddSection("Draco");
local ToggleBlazeEmber = Tabs.Sea:AddToggle("ToggleBlazeEmber", {Title="Lụm Lửa Đỏ",Description="",Default=false});
ToggleBlazeEmber:OnChanged(function(Value)
	_G.AutoBlazeEmber = Value;
end);
spawn(function()
	while wait() do
		if _G.AutoBlazeEmber then
			pcall(function()
				game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Net"):WaitForChild("RE/DragonDojoEmber"):FireServer();
			end);
		end
	end
end);
local ToggleReceiveQuest = Tabs.Sea:AddToggle("ToggleReceiveQuest", {Title="Nhận Nhiệm Vụ Lửa Đỏ",Description="Bật Lên 1 Lần Là Nhận 1 Nhận Nữa Thì Tắt Bật Lại",Default=false});
ToggleReceiveQuest:OnChanged(function(Value)
	_G.AutoReceiveQuest = Value;
	if _G.AutoReceiveQuest then
		game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(5661.5322265625, 1013.0907592773438, -334.9649963378906));
		Tween2(CFrame.new(5814.42724609375, 1208.3267822265625, 884.5785522460938));
		spawn(function()
			pcall(function()
				while wait() do
					local args = {[1]={Context="RequestQuest"}};
					game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/DragonHunter"):InvokeServer(unpack(args));
					local checkArgs = {[1]={Context="Check"}};
					local response = game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/DragonHunter"):InvokeServer(unpack(checkArgs));
				end
			end);
		end);
	end
end);
local BlazeEmberQuestStatus = Tabs.Sea:AddParagraph({Title="Trạng Thái Nhiệm Vụ Lửa Đỏ",Content=""});
spawn(function()
	pcall(function()
		while wait() do
			local args = {[1]={Context="Check"}};
			local response = game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/DragonHunter"):InvokeServer(unpack(args));
			if (typeof(response) == "table") then
				for key, value in pairs(response) do
					if (value == "Defeat 3 Venomous Assailants on Hydra Island.") then
						BlazeEmberQuestStatus:SetDesc("Defeat 3 Venomous Assailants on Hydra Island.");
					elseif (value == "Defeat 3 Hydra Enforcers on Hydra Island.") then
						BlazeEmberQuestStatus:SetDesc("Defeat 3 Hydra Enforcers on Hydra Island.");
					elseif (value == "Destroy 10 trees on Hydra Island.") then
						BlazeEmberQuestStatus:SetDesc("Destroy 10 trees on Hydra Island.");
					end
				end
			else
				print(response);
			end
		end
	end);
end);
local ToggleHydraTree = Tabs.Sea:AddToggle("ToggleHydraTree", {Title="Phá Cây Ở Đảo Hydra",Description="",Default=false});
ToggleHydraTree:OnChanged(function(Value)
	_G.AutoHydraTree = Value;
end);
local function sendSkillKey(skillKey)
	local virtualInputManager = game:GetService("VirtualInputManager");
	virtualInputManager:SendKeyEvent(true, skillKey, false, game);
	virtualInputManager:SendKeyEvent(false, skillKey, false, game);
end
local function equipAndUseSkill(toolType)
	local player = game.Players.LocalPlayer;
	local backpack = player.Backpack;
	for _, item in pairs(backpack:GetChildren()) do
		if (item:IsA("Tool") and (item.ToolTip == toolType)) then
			item.Parent = player.Character;
			for _, skill in ipairs({"Z","X","C","V","F"}) do
				wait();
				pcall(function()
					sendSkillKey(skill);
				end);
			end
			item.Parent = backpack;
			break;
		end
	end
end
local targets = {CFrame.new(5288.61962890625, 1005.4000244140625, 392.43011474609375),CFrame.new(5343.39453125, 1004.1998901367188, 361.0687561035156),CFrame.new(5235.78564453125, 1004.1998901367188, 431.4530944824219),CFrame.new(5321.30615234375, 1004.1998901367188, 440.8951416015625),CFrame.new(5258.96484375, 1004.1998901367188, 345.5052490234375)};
spawn(function()
	while wait() do
		if _G.AutoHydraTree then
			AutoHaki();
			for _, target in ipairs(targets) do
				if not _G.AutoHydraTree then
					break;
				end
				Tween2(target);
				wait();
				local character = game.Players.LocalPlayer.Character;
				if (character and character:FindFirstChild("HumanoidRootPart")) then
					local distance = (character.HumanoidRootPart.Position - target.Position).Magnitude;
					if (distance <= 1) then
						equipAndUseSkill("Melee");
						equipAndUseSkill("Sword");
						equipAndUseSkill("Gun");
					end
				end
			end
		end
	end
end);
Blaze:AddButton({Title="Bay Đến Khu Vực Dragon Dojo",Description="",Callback=function()
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(5661.5322265625, 1013.0907592773438, -334.9649963378906));
	Tween2(CFrame.new(5814.42724609375, 1208.3267822265625, 884.5785522460938));
end});
Blaze:AddButton({Title="Chế Tạo Volcanic Magnet",Description="",Callback=function()
	local args = {[1]="CraftItem",[2]="Craft",[3]="Volcanic Magnet"};
	game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer(unpack(args));
end});
local ToggleCollectFireFlowers = Tabs.Sea:AddToggle("ToggleCollectFireFlowers", {Title="Lụm Hoa Đỏ",Description="",Default=false});
ToggleCollectFireFlowers:OnChanged(function(Value)
	_G.AutoCollectFireFlowers = Value;
end);
spawn(function()
	while wait() do
		if _G.AutoCollectFireFlowers then
			local fireFlowersFolder = workspace:FindFirstChild("FireFlowers");
			if fireFlowersFolder then
				for _, obj in pairs(fireFlowersFolder:GetChildren()) do
					if (obj:IsA("Model") and obj.PrimaryPart) then
						local flowerPos = obj.PrimaryPart.Position;
						local playerPos = game.Players.LocalPlayer.Character.HumanoidRootPart.Position;
						local distance = (flowerPos - playerPos).Magnitude;
						if (distance <= 1) then
							game:GetService("VirtualInputManager"):SendKeyEvent(true, "E", false, game);
							wait(1.5);
							game:GetService("VirtualInputManager"):SendKeyEvent(false, "E", false, game);
						else
							Tween2(CFrame.new(flowerPos));
						end
					end
				end
			end
		end
	end
end);
local ToggleWhiteBelt = Tabs.Sea:AddToggle("ToggleWhiteBelt", {Title="Cày Đai Trắng",Description="",Default=false});
ToggleWhiteBelt:OnChanged(function(Value)
	_G.AutoLevel = Value;
	if Value then
		local args = {[1]={NPC="Dojo Trainer",Command="RequestQuest"}};
		game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/InteractDragonQuest"):InvokeServer(unpack(args));
		spawn(function()
			while _G.AutoLevel do
				local claimArgs = {[1]={NPC="Dojo Trainer",Command="ClaimQuest"}};
				game:GetService("ReplicatedStorage").Modules.Net:FindFirstChild("RF/InteractDragonQuest"):InvokeServer(unpack(claimArgs));
				wait();
			end
		end);
	end
end);
local DracoV4 = Tabs.Sea:AddParagraph({Title="Hoàn Thành Ải Draco V4 (Sớm Ra)",Content=""});
local ToggleTrialTeleport = Tabs.Sea:AddToggle("ToggleTrialTeleport", {Title="Bay Đến Cửa Trial Tộc Draco",Description="",Default=false});
ToggleTrialTeleport:OnChanged(function(Value)
	_G.AutoTrialTeleport = Value;
end);
spawn(function()
	while wait() do
		if _G.AutoTrialTeleport then
			local trialTeleport = workspace.Map.PrehistoricIsland:FindFirstChild("TrialTeleport");
			if (trialTeleport and trialTeleport:IsA("Part")) then
				Tween2(CFrame.new(trialTeleport.Position));
			end
		end
	end
end);
local Volcano = Tabs.Sea:AddSection("Đảo Dung Nham");
local Prehistoric = Tabs.Sea:AddParagraph({Title="Trạng Thái Đảo Dung Nham",Content=""});
spawn(function()
	pcall(function()
		while wait() do
			if ggame:GetService("Workspace").Map:FindFirstChild("PrehistoricIsland") then
				Prehistoric:SetDesc("Đảo Dung Nham: ✅️");
			else
				Prehistoric:SetDesc("Đảo Dung Nham: ❌️");
			end
		end
	end);
end);
local ToggleTPVolcano = Tabs.Sea:AddToggle("ToggleTPVolcano", {Title="Bay Đến Đảo Dung Nham",Description="",Default=false});
ToggleTPVolcano:OnChanged(function(Value)
	_G.TweenToPrehistoric = Value;
end);
Options.ToggleTPVolcano:SetValue(false);
spawn(function()
	local island;
	while not island do
		island = game:GetService("Workspace").Map:FindFirstChild("PrehistoricIsland");
		wait();
	end
	while wait() do
		if _G.TweenToPrehistoric then
			local prehistoricIslandCore = game:GetService("Workspace").Map:FindFirstChild("PrehistoricIsland");
			if prehistoricIslandCore then
				local relic = prehistoricIslandCore:FindFirstChild("Core") and prehistoricIslandCore.Core:FindFirstChild("PrehistoricRelic");
				local skull = relic and relic:FindFirstChild("Skull");
				if skull then
					Tween2(CFrame.new(skull.Position));
					_G.TweenToPrehistoric = false;
				end
			end
		end
	end
end);
local ToggleDefendVolcano = Tabs.Sea:AddToggle("ToggleDefendVolcano", {Title="Phòng Thủ",Description="",Default=false});
ToggleDefendVolcano:OnChanged(function(Value)
	_G.AutoDefendVolcano = Value;
end);
local ToggleMelee = Tabs.Sea:AddToggle("ToggleMelee", {Title="Dùng Melee",Description="",Default=false});
ToggleMelee:OnChanged(function(Value)
	_G.UseMelee = Value;
end);
local ToggleSword = Tabs.Sea:AddToggle("ToggleSword", {Title="Dùng Sword",Description="",Default=false});
ToggleSword:OnChanged(function(Value)
	_G.UseSword = Value;
end);
local ToggleGun = Tabs.Sea:AddToggle("ToggleGun", {Title="Dùng Gun",Description="",Default=false});
ToggleGun:OnChanged(function(Value)
	_G.UseGun = Value;
end);
local function useSkill(skillKey)
	game:GetService("VirtualInputManager"):SendKeyEvent(true, skillKey, false, game);
	game:GetService("VirtualInputManager"):SendKeyEvent(false, skillKey, false, game);
end
local function removeLava()
	local interiorLavaModel = game.Workspace.Map.PrehistoricIsland.Core:FindFirstChild("InteriorLava");
	if (interiorLavaModel and interiorLavaModel:IsA("Model")) then
		interiorLavaModel:Destroy();
	end
	local prehistoricIsland1 = game.Workspace.Map:FindFirstChild("PrehistoricIsland");
	if prehistoricIsland1 then
		for _, descendant in pairs(prehistoricIsland1:GetDescendants()) do
			if (descendant:IsA("Part") and descendant.Name:lower():find("lava")) then
				descendant:Destroy();
			end
		end
	end
	local prehistoricIsland2 = game.Workspace.Map:FindFirstChild("PrehistoricIsland");
	if prehistoricIsland2 then
		for _, model in pairs(prehistoricIsland2:GetDescendants()) do
			if model:IsA("Model") then
				for _, child in pairs(model:GetDescendants()) do
					if (child:IsA("MeshPart") and child.Name:lower():find("lava")) then
						child:Destroy();
					end
				end
			end
		end
	end
end
local function findValidRock()
	local volcanoRocksFolder = game.Workspace.Map.PrehistoricIsland.Core.VolcanoRocks;
	for _, Rock in pairs(volcanoRocksFolder:GetChildren()) do
		if Rock:IsA("Model") then
			local volcanorock = Rock:FindFirstChild("volcanorock");
			if (volcanorock and volcanorock:IsA("MeshPart")) then
				local color = volcanorock.Color;
				if ((color == Color3.fromRGB(185, 53, 56)) or (color == Color3.fromRGB(185, 53, 57))) then
					return volcanorock;
				end
			end
		end
	end
	return nil;
end
local function equipAndUseSkill(toolType)
	local player = game.Players.LocalPlayer;
	local backpack = player.Backpack;
	for _, item in pairs(backpack:GetChildren()) do
		if (item:IsA("Tool") and (item.ToolTip == toolType)) then
			item.Parent = player.Character;
			for _, skill in ipairs({"Z","X","C","V","F"}) do
				wait();
				pcall(function()
					useSkill(skill);
				end);
			end
			item.Parent = backpack;
			break;
		end
	end
end
spawn(function()
	while wait() do
		if _G.AutoDefendVolcano then
			AutoHaki();
			pcall(removeLava);
			local currentTarget = findValidRock();
			if currentTarget then
				local targetPosition = CFrame.new(currentTarget.Position + Vector3.new(0, 0, 0));
				Tween2(targetPosition);
				local color = currentTarget.Color;
				if ((color ~= Color3.fromRGB(185, 53, 56)) and (color ~= Color3.fromRGB(185, 53, 57))) then
					currentTarget = findValidRock();
				else
					local currentPosition = game.Players.LocalPlayer.Character.HumanoidRootPart.Position;
					local distance = ((currentPosition - currentTarget.Position) - Vector3.new(0, 0, 0)).Magnitude;
					if (distance <= 1) then
						if _G.UseMelee then
							equipAndUseSkill("Melee");
						end
						if _G.UseSword then
							equipAndUseSkill("Sword");
						end
						if _G.UseGun then
							equipAndUseSkill("Gun");
						end
					end
					_G.TweenToPrehistoric = false;
				end
			else
				_G.TweenToPrehistoric = true;
			end
		end
	end
end);
local ToggleKillAura = Tabs.Sea:AddToggle("ToggleKillAura", {Title="Đấm Golems Aura",Description="",Default=false});
ToggleKillAura:OnChanged(function(Value)
	KillAura = Value;
end);
Options.ToggleKillAura:SetValue(false);
spawn(function()
	while wait() do
		if KillAura then
			pcall(function()
				for i, v in pairs(game.Workspace.Enemies:GetDescendants()) do
					if (v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and (v.Humanoid.Health > 0)) then
						repeat
							task.wait();
							sethiddenproperty(game:GetService("Players").LocalPlayer, "SimulationRadius", math.huge);
							v.Humanoid.Health = 0;
							v.HumanoidRootPart.CanCollide = false;
						until not KillAura or not v.Parent or (v.Humanoid.Health <= 0) 
					end
				end
			end);
		end
	end
end);
local ToggleCollectBone = Tabs.Sea:AddToggle("ToggleCollectBone", {Title="Lụm Xương",Description="",Default=false});
ToggleCollectBone:OnChanged(function(Value)
	_G.AutoCollectBone = Value;
end);
spawn(function()
	while wait() do
		if _G.AutoCollectBone then
			for _, obj in pairs(workspace:GetDescendants()) do
				if (obj:IsA("BasePart") and (obj.Name == "DinoBone")) then
					Tween2(CFrame.new(obj.Position));
				end
			end
		end
	end
end);
local ToggleCollectEgg = Tabs.Sea:AddToggle("ToggleCollectEgg", {Title="Lụm Trứng",Description="",Default=false});
ToggleCollectEgg:OnChanged(function(Value)
	_G.AutoCollectEgg = Value;
end);
spawn(function()
	while wait() do
		if _G.AutoCollectEgg then
			local dragonEggs = workspace.Map.PrehistoricIsland.Core.SpawnedDragonEggs:GetChildren();
			if (#dragonEggs > 0) then
				local randomEgg = dragonEggs[math.random(1, #dragonEggs)];
				if (randomEgg:IsA("Model") and randomEgg.PrimaryPart) then
					Tween2(randomEgg.PrimaryPart.CFrame);
					local playerPosition = game.Players.LocalPlayer.Character.HumanoidRootPart.Position;
					local eggPosition = randomEgg.PrimaryPart.Position;
					local distance = (playerPosition - eggPosition).Magnitude;
					if (distance <= 1) then
						game:GetService("VirtualInputManager"):SendKeyEvent(true, "E", false, game);
						wait(1.5);
						game:GetService("VirtualInputManager"):SendKeyEvent(false, "E", false, game);
					end
				end
			end
		end
	end
end);
Fluent:Notify({Title="Ldt Hub",Content="Tải Xong",Duration=10});