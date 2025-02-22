#Requires AutoHotkey v2.0
#SingleInstance Force

; 检查管理员权限并自动提升
if !A_IsAdmin {
	try {
		if A_IsCompiled
			Run '*RunAs "' A_ScriptFullPath '" /restart'
		else
			Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
		ExitApp
	}
}

; 设置全局变量和配置文件路径
global configPath := A_ScriptDir "\settings.ini"
global isRunning := false
global keySettings := Map()
global SetupGui
global timeFactor := 1.0  ; 添加时间系数全局变量
global startKey := "F1"    ; 添加启动按键设置
global stopKey := "F2"     ; 添加停止按键设置

; 加载配置
LoadConfig() {
    global keySettings, configPath, timeFactor, timeFactorInput, startKey, stopKey, startKeyInput, stopKeyInput
    try {
        if FileExist(configPath) {
            ; 读取时间系数
            timeFactor := Float(IniRead(configPath, "Settings", "timeFactor", "1.0"))
            timeFactorInput.Text := timeFactor

            ; 读取控制按键
            startKey := IniRead(configPath, "Controls", "startKey", "F1")
            stopKey := IniRead(configPath, "Controls", "stopKey", "F2")
            startKeyInput.Text := startKey
            stopKeyInput.Text := stopKey
            
            ; 更新热键绑定
            UpdateHotkeys()

            ; 读取所有section
            IniRead_sections := IniRead(configPath)
            Loop Parse, IniRead_sections, "`n", "`r" {
                key := A_LoopField
                if (key != "" && key != "Settings" && key != "Controls") {
                    before := IniRead(configPath, key, "before", "0")
                    after := IniRead(configPath, key, "after", "0")
                    keySettings[key] := {before: Integer(before), after: Integer(after)}
                }
            }
        }
    }
}

; 保存配置
SaveConfig() {
    global keySettings, configPath, timeFactor, startKey, stopKey
    try {
        ; 先删除已存在的配置文件
        if FileExist(configPath)
            FileDelete(configPath)
            
        ; 保存时间系数
        IniWrite(timeFactor, configPath, "Settings", "timeFactor")
        
        ; 保存控制按键
        IniWrite(startKey, configPath, "Controls", "startKey")
        IniWrite(stopKey, configPath, "Controls", "stopKey")
        
        ; 保存每个按键的设置
        for key, settings in keySettings {
            IniWrite(settings.before, configPath, key, "before")
            IniWrite(settings.after, configPath, key, "after")
        }
    }
}

; 创建设置界面
SetupGui := Gui("+AlwaysOnTop", "按键循环设置 [已停止]")

; 添加ListView用于显示按键设置
lv := SetupGui.Add("ListView", "w400 h200", ["按键", "前摇时间(ms)", "后摇时间(ms)"])

; 添加编辑区域
SetupGui.Add("Text",, "按键:")
keyInput := SetupGui.Add("Edit", "w50")
SetupGui.Add("Text",, "前摇时间(ms):")
beforeInput := SetupGui.Add("Edit", "w100", "0")
SetupGui.Add("Text",, "后摇时间(ms):")
afterInput := SetupGui.Add("Edit", "w100", "0")

; 添加时间系数调节
SetupGui.Add("Text", "x+20", "时间系数(倍):")
timeFactorInput := SetupGui.Add("Edit", "w60", "1.0")
SetupGui.Add("Button", "w100", "应用系数").OnEvent("Click", ApplyTimeFactor)

; 添加控制按键设置
SetupGui.Add("Text", "xm", "启动按键:")
startKeyInput := SetupGui.Add("Edit", "w50", startKey)
SetupGui.Add("Text", "x+20", "停止按键:")
stopKeyInput := SetupGui.Add("Edit", "w50", stopKey)
SetupGui.Add("Button", "x+10 w100", "更新控制按键").OnEvent("Click", UpdateControlKeys)

; 添加按钮
SetupGui.Add("Button", "w100", "添加按键").OnEvent("Click", AddKey)
SetupGui.Add("Button", "w100 x+10", "删除选中").OnEvent("Click", RemoveKey)

SetupGui.Show()

; 更新控制按键
UpdateControlKeys(*) {
    global startKey, stopKey
    newStartKey := startKeyInput.Text
    newStopKey := stopKeyInput.Text
    
    if (newStartKey != "" && newStopKey != "") {
        startKey := newStartKey
        stopKey := newStopKey
        UpdateHotkeys()
        SaveConfig()
    }
}

; 更新热键绑定
UpdateHotkeys() {
    global startKey, stopKey
    
    ; 移除旧的热键绑定
    try Hotkey startKey, "Off"
    try Hotkey stopKey, "Off"
    
    ; 添加新的热键绑定
    Hotkey startKey, StartLoop
    Hotkey stopKey, StopLoop
}

; 启动循环函数
StartLoop(*) {
    global isRunning, SetupGui
    if !isRunning {
        isRunning := true
        try {
            SetupGui.Title := "按键循环设置 [运行中]"
            InitLoop()  ; 重命名原来的StartLoop为InitLoop
        }
    }
}

; 停止循环函数
StopLoop(*) {
    global isRunning, SetupGui
    isRunning := false
    try {
        SetupGui.Title := "按键循环设置 [已停止]"
    }
}

; 添加按键设置
AddKey(*) {
    global keySettings
    if keyInput.Text != "" {
        key := keyInput.Text
        before := Integer(beforeInput.Text)
        after := Integer(afterInput.Text)
        keySettings[key] := {before: before, after: after}
        RefreshListView()
        SaveConfig()  ; 保存配置
    }
}

; 删除选中的按键
RemoveKey(*) {
    global keySettings
    if row := lv.GetNext() {
        key := lv.GetText(row, 1)
        keySettings.Delete(key)
        RefreshListView()
        SaveConfig()  ; 保存配置
    }
}

; 刷新ListView显示
RefreshListView() {
    lv.Delete()
    for key, settings in keySettings {
        lv.Add(, key, settings.before, settings.after)
    }
}

; 初始化循环（原StartLoop函数重命名）
InitLoop() {
	global isRunning, keySettings, keyStates
	; 初始化按键状态Map
	keyStates := Map()
	
	; 设置每个按键的初始状态
	for key, settings in keySettings {
		keyStates[key] := {
			lastTick: A_TickCount,  ; 使用系统计时器
			phase: "before",        ; 当前阶段：before(前摇) / press(按下) / after(后摇)
			settings: settings      ; 按键设置
		}
	}
	
	; 启动定时器，每1ms检查一次
	SetTimer(TimerRoutine, 1)
}

; 定时器回调函数
TimerRoutine() {
	global isRunning, keyStates
	
	if (!isRunning) {
		SetTimer(TimerRoutine, 0)  ; 停止定时器
		return
	}
	
	currentTick := A_TickCount
	
	; 处理每个按键的状态
	for key, state in keyStates {
		elapsedTime := currentTick - state.lastTick
		
		; 根据不同阶段处理
		switch state.phase {
			case "before":
				if (elapsedTime >= state.settings.before) {
					SendInput("{Blind}{" key " down}")  ; 按下按键
					state.lastTick := currentTick
					state.phase := "press"
				}
			case "press":
				SendInput("{Blind}{" key " up}")    ; 释放按键
				state.lastTick := currentTick
				state.phase := "after"
			case "after":
				if (elapsedTime >= state.settings.after) {
					state.lastTick := currentTick
					state.phase := "before"    ; 重新开始循环
				}
		}
	}
}

; 应用时间系数
ApplyTimeFactor(*) {
    global keySettings, timeFactor
    newFactor := Float(timeFactorInput.Text)
    if (newFactor > 0) {
        timeFactor := newFactor
        for key, settings in keySettings {
            settings.before := Integer(settings.before * newFactor)
            settings.after := Integer(settings.after * newFactor)
        }
        RefreshListView()
        SaveConfig()
    }
}

; 在程序启动时加载配置
LoadConfig()
RefreshListView()

; 在程序退出时保存配置
OnExit((*) => SaveConfig())
