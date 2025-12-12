--[[
Cct与机械动力动力调速器。
基于一下的内容修改了部分内容，添加了一些适配。
【[CC]我的世界CC自动化控制程序部署教程】 https://www.bilibili.com/video/BV1W1421t7Ui/?share_source=copy_web&vd_source=7ef3320ed925f229df9b2dfaa1f0ee49
改为了事件触发的方法，原本按照creat的手册，应力表会加载事件，但没有触发，自己添加一个添加事件的函数，291行 ,有问题可以修改

简化了放置规则，只需要有转速控制器和应力表，且连接到cct计算机即可，可以是放在电脑旁边，也可以拉根网线拉到远处，建议应力表放在输入端的位置。
允许破坏除电脑本体外的任意设备，设备重连时则继续运行。

允许将显示内容显示到屏幕。
打开电脑按下m键，自动查询到屏幕，允许热切换屏幕。

设置了三种不同的调速模式。
1  最大应力分配的方式，能够尽可能的将效率拉到最大，使用百分比能够达到90%以上。用于绝大部分范围的调速。

2  有些时候你的应力源质量并不好，它可能存在波动，或者应力消耗的一端也出现波动，这种情况比较少见，但也确实存在。
这种较差质量的网络会造成难以调速，或调速非常不稳定。此时可以在电脑里按下数字键2，开启第2种模式，现在会自动过滤30%的应力波动，并且会保留10%的余量，用来防止应力过载。
可以通过修改"boongkiang"，改变
当然这种情况更建议改进机器的工艺。

3   仅仅在应力过载时调速。这种模式下仅仅应力过载的时候才会调速，也就是说你的转速并不会上升，只会一直下降，直到你手动调整，不过暂时没有想到有什么用。

转速为0的情况:转速低于minimumRotationSpeed最低转速时直接停机，隔离输入与输出的应力网络
恢复方法：
通常应力足够会自动恢复，但注意应力表放置在输入位置。应力表如果在输出位置，会发生自锁，需要手动复位一下
手动复位方法：1. 任意更新设备；比如断开外设连接、破坏应力表。  2. 手动调整转速；
]]
local maximumRotationSpeed = 256
local minimumRotationSpeed = 16
local bodongliang = 0.3 --波动变化量的参数，0.3即30%的波动
local Stressometer--应力表
local RotationalSpeedController--转速控制器
local ok = false--是否可以运行
local spressForEachOnePRM = 0--应力功率
local modeNum=1--模式控制
local oldStress = 0--记录总应力
local oldStressCapacity=0--记录承载应力
local is_timer_id=-1----多次修改转速间隔限制计时器id
local is_run=true--多次修改转速间隔限制
----------------------------------------------------------
--尝试寻找应力表。
local function findStressometer()
    Stressometer = peripheral.find("Create_Stressometer")
    if Stressometer==nil then
        print("Stressometer not found.")
        return false
    end
    return true
end

--尝试寻找转速控制器。
local function findRotationalSpeedController()
    RotationalSpeedController = peripheral.find("Create_RotationSpeedController")
    if RotationalSpeedController==nil then
        print("RotationalSpeedController not found.")
        return false
    end
    return true
end

--获取当前转速
local function getCurrentRotationSpeed()
    return RotationalSpeedController.getTargetSpeed()
end

--获取当前使用应力0,总应力1
local function getStress(num)
    if num==nil or num ==0 then
        return Stressometer.getStress()
    else
        return Stressometer.getStressCapacity()
    end
end

--设置转速
local function setCurrentRotationSpeed(speed)
    if speed>maximumRotationSpeed then
        speed=maximumRotationSpeed
    end
    return RotationalSpeedController.setTargetSpeed(speed)
end

--返回应力网络中固定应力的应力值。
local function getStableStress()
    local currentRotationSpeed = getCurrentRotationSpeed() -- 获取当前转速
    local currentStress = getStress(0) -- 获取当前应力
    local newRotationalSpeed = 0                           -- 新应力
    local stableStress = 0

    -- 根据情况调整转速
    if currentRotationSpeed <= minimumRotationSpeed+1 then
        -- 使用增加转速的策略
        newRotationalSpeed = currentRotationSpeed + 1
    else
        -- 使用减少转速的策略
        newRotationalSpeed = currentRotationSpeed - 1
    end

    setCurrentRotationSpeed(newRotationalSpeed)   -- 设置新转速
    sleep(0.1)                                    -- 等待应力稳定
    local newStress = getStress(0)          -- 获取新应力
    setCurrentRotationSpeed(currentRotationSpeed) -- 还原转速
    spressForEachOnePRM = math.abs(newStress - currentStress)  --应力功率
    print("spressForEachOnePRM: " .. tostring(spressForEachOnePRM))
    stableStress = currentStress - (spressForEachOnePRM * currentRotationSpeed) -- 计算固定应力的应力值
    print("currentStress: " .. tostring(currentStress))
    print("Stable Stress: " .. tostring(stableStress))
    return stableStress
end

--获取目标最大转速
local function getMaxTagetRotationSpeed()
    local nowStress= getStress(1)
    local tagetPRM=getCurrentRotationSpeed()--当前转速
    --应力百分比大于
    if ((nowStress-getStress(0))/nowStress>0.3)and tagetPRM==maximumRotationSpeed then
        return maximumRotationSpeed
    end
    --动态应力变化适配
    if modeNum==2 then
        nowStress=(nowStress+oldStress)*0.45
    end
    local stableStress = getStableStress() --固定应力
    tagetPRM= (nowStress - stableStress) / spressForEachOnePRM
    tagetPRM=math.floor(tagetPRM)--向下取整
    if tagetPRM >= maximumRotationSpeed then
        tagetPRM = maximumRotationSpeed
    end
    if tagetPRM <= minimumRotationSpeed then
        return 0
    end
    if tostring(tagetPRM) == "nan"  then
        return 0
    end
    return tagetPRM
end
--调速
local function adapt()
    if not is_run then
        return
    end
    local newStress=getStress(1)
    local newtressCapacity=getStress(0)
    --调速后转速
    local TagetRotationSpeed=getMaxTagetRotationSpeed()
    print("Stress Changed, Trying to set new rotation speed.")
    print("----------------------------------------------")
    print("Current Rotation Speed: " .. TagetRotationSpeed)
    print("Current Stress: " .. newStress)
    setCurrentRotationSpeed(TagetRotationSpeed)
    oldStress = newStress
    oldStressCapacity=newtressCapacity
    is_timer_id=os.startTimer(0.3)
    is_run=false
end

--初始化
local function first()
    print("----------------------------------------------")
    if findStressometer() and findRotationalSpeedController() then
        ok=true
        oldStress=getStress(1)
        if is_timer_id~=-1 then
            is_run=true
            os.cancelTimer(is_timer_id)
        end
        adapt()
        return
    end
    print("Waiting for next time initialization...")
    ok=false
end

--模式修改的提示信息
local function message(mode)
    local my_window_1,my_window_2
    term.clear()
    local lx,lh=term.getSize()
    my_window_1 = window.create(term.current(), 1,1, lx, 7)
    my_window_2 = window.create(term.current(), 1,7, lx, lh-7)
    term.redirect(my_window_2)
    lx,lh=nil,nil
    my_window_1.write("press the corresponding key to modify:")
    my_window_1.setCursorPos(1,2)
    my_window_1.write("1: Maximum stress Tracking")
    my_window_1.setCursorPos(1,3)
    my_window_1.write("2: Dynamic speed control")
    my_window_1.setCursorPos(1,4)
    my_window_1.write("3: Overload adjustment only")
    my_window_1.setCursorPos(1,5)
    my_window_1.write("M: Connect to the screen")
    my_window_1,my_window_2=nil,nil
end

--重定向到屏幕。
local function findMonitor()
    local monitor = peripheral.find("monitor")
    if monitor==nil then
        print("monitor not found.")
        return
    end
    term.redirect(monitor)
    message()
end

--key处理
local function key (key)
    if key==49 then
        modeNum=1
        printError("modeNum is :"..modeNum)
        if ok then
            adapt()
        end
    elseif key==50 then
        modeNum=2
        printError("modeNum is :"..modeNum)
        if ok then
            adapt()
        end
    elseif key==51  then
        modeNum=3
        printError("modeNum is :"..modeNum)
        if ok then
            adapt()
        end
    elseif key==333 then
        os.queueEvent("overstressed")
        printError("add_overstressed")
    elseif key==77 then
        findMonitor()
    end
end
--timer事件处理
local function timer_solve(timer_id)
    --多次修改转速的间隔限制
    if timer_id==is_timer_id then
        is_run=true
        os.cancelTimer(timer_id)
        is_timer_id=-1
    end
end


--事件触发
local function EventManager()
    local event,param1,param2,param3 = os.pullEvent()

    if(event=="key")then
           key(param1)
    end
    --丢失设备的判断
    if (not ok) and event~="peripheral" then
        return
    end
    if(event=="overstressed")then
        adapt()
    elseif event=="stress_change" then
        if modeNum==2 then
            if ((math.abs((getStress(1)-oldStress)/oldStress)>bodongliang) or (math.abs((getStress(0)-oldStressCapacity)/oldStressCapacity))>bodongliang) then
                adapt()
            end
        elseif modeNum==3 then
            return
        else
            adapt()
        end
    elseif (event=="timer")then
        timer_solve(param1)
    elseif(event=="peripheral")then
        first()
    elseif(event=="peripheral_detach")then
        first()
    end
end

--[[**
原本按照以下手册，应力表会加载事件，但实际没有，自己添加一个
https://wiki.createmod.net/users/cc-tweaked-integration/stressometer#getStress
============
Stressometer···应力表
Event: overstressed···Triggers whenever the network becomes overstressed.
每当网络过载时触发。
------------------------------
Event: stress_change···Triggers whenever the network's stress changes.
每当网络压力变化时触发。
Returns  number The total stress level in SU.
 SU 应力表的总压力水平。
number The total stress capacity in SU.
 SU 应力表中的总应力承载能力。
**]]
local function create_queueEvent()
    while true do
        if ok then
            local newStress = getStress(1)--计算总应力
            local newcurrentStress=getStress(0)--当前使用应力
            if oldStress ~= newStress or oldStressCapacity~=newcurrentStress then
                --oldStress = newStress
                --oldStressCapacity=newcurrentStress
                os.queueEvent("stress_change",newStress,newcurrentStress)
            end
            if newStress<newcurrentStress then
                os.queueEvent("overstressed")
            end
        end
        sleep(0.8)
    end

end




local function main()
    message()
    first()
    while true do
        if(EventManager)then
            EventManager()
        end
    end
end

parallel.waitForAll(main, create_queueEvent)
