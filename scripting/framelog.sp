#include <sourcemod>

float g_fPrevEngineTime;

int g_iFrameTimeIndex;
bool g_bProfilingEnabled;
int g_iProfilingTicks;
char g_sProfilingPrefix[64];
int g_iFramesProcessed;

File g_hFile10Ticks;
File g_hFile100Ticks;
File g_hFile1000Ticks;
File g_hFileFrameTimes;

ConVar g_hCvarEnable10Ticks;
ConVar g_hCvarEnable100Ticks;
ConVar g_hCvarEnable1000Ticks;
ConVar g_hCvarEnableFrameTimes;

#define BUFFER_SIZE 256
#define MAX_PREFIX_LENGTH 64
#define FRAME_TIME_ARRAY_SIZE 10000

float g_fFrameTimeArray[FRAME_TIME_ARRAY_SIZE];

public void OnPluginStart()
{
    g_fPrevEngineTime = 0.0;
    g_iFrameTimeIndex = 0;
    g_bProfilingEnabled = false;
    g_iProfilingTicks = 0;
    g_sProfilingPrefix[0] = '\0';

    g_hCvarEnable10Ticks = CreateConVar("sm_frametime_enable_10_ticks", "1", "Enable frame time deviation logging for 10 ticks");
    g_hCvarEnable100Ticks = CreateConVar("sm_frametime_enable_100_ticks", "1", "Enable frame time deviation logging for 100 ticks");
    g_hCvarEnable1000Ticks = CreateConVar("sm_frametime_enable_1000_ticks", "1", "Enable frame time deviation logging for 1000 ticks");
    g_hCvarEnableFrameTimes = CreateConVar("sm_frametime_enable_per_tick", "1", "Enable frame time per tick logging");

    AutoExecConfig(true, "frametime_deviation");

    RegConsoleCmd("sm_framelog", Command_Framelog, "Enables frame time profiling for a specified number of ticks (1 to 9999)");

    CreateLogDirectory();

    // Add debug print statements to verify ConVar values
    PrintToServer("ConVar sm_frametime_enable_10_ticks: %d", g_hCvarEnable10Ticks.BoolValue);
    PrintToServer("ConVar sm_frametime_enable_100_ticks: %d", g_hCvarEnable100Ticks.BoolValue);
    PrintToServer("ConVar sm_frametime_enable_1000_ticks: %d", g_hCvarEnable1000Ticks.BoolValue);
    PrintToServer("ConVar sm_frametime_enable_per_tick: %d", g_hCvarEnableFrameTimes.BoolValue);
}

public void OnPluginEnd()
{
    if (g_hFile10Ticks != null)
        CloseHandle(g_hFile10Ticks);

    if (g_hFile100Ticks != null)
        CloseHandle(g_hFile100Ticks);

    if (g_hFile1000Ticks != null)
        CloseHandle(g_hFile1000Ticks);

    if (g_hFileFrameTimes != null)
        CloseHandle(g_hFileFrameTimes);
}

public Action Command_Framelog(int client, int args)
{
    if (args != 2)
    {
        ReplyToCommand(client, "Usage: !framelog <prefix> <ticks>");
        return Plugin_Handled;
    }

    char sPrefix[MAX_PREFIX_LENGTH];
    GetCmdArg(1, sPrefix, sizeof(sPrefix));

    if (strlen(sPrefix) >= sizeof(g_sProfilingPrefix))
    {
        ReplyToCommand(client, "Prefix too long.");
        return Plugin_Handled;
    }

    int iTicks = GetCmdArgInt(2);

    if (iTicks <= 0 || iTicks >= 10000)
    {
        ReplyToCommand(client, "Invalid number of ticks specified.");
        return Plugin_Handled;
    }

    StartProfiling(sPrefix, iTicks);

    ReplyToCommand(client, "Frame time profiling enabled for %d ticks with prefix '%s'.", iTicks, sPrefix);

    return Plugin_Handled;
}

void StartProfiling(const char[] prefix, int ticks)
{
    g_bProfilingEnabled = true;
    g_iProfilingTicks = ticks;
    strcopy(g_sProfilingPrefix, sizeof(g_sProfilingPrefix), prefix);

    if (CreateLogFiles())
    {
        PrintToChatAll("Frame time profiling started for %d ticks with prefix '%s'.", ticks, prefix);
        LogMessage("Frame time profiling started for %d ticks with prefix '%s'.", ticks, prefix);
    }
    else
    {
        PrintToChatAll("Failed to start frame time profiling. Check server logs for details.");
        LogError("Failed to start frame time profiling.");
        StopProfiling();
    }
}

void StopProfiling()
{
    PrintToServer("Stopping profiling...");

    g_bProfilingEnabled = false;
    g_iProfilingTicks = 0;
    g_sProfilingPrefix[0] = '\0';
    g_iFramesProcessed = 0;

    CloseLogFiles();

    PrintToChatAll("Frame time profiling completed.");
    LogMessage("Frame time profiling completed.");
}

public void OnGameFrame()
{
    if (!g_bProfilingEnabled)
    {
        return;
    }

    float fCurrentEngineTime = GetEngineTime();
    float fFrameTime = fCurrentEngineTime - g_fPrevEngineTime;
    g_fPrevEngineTime = fCurrentEngineTime;

    g_fFrameTimeArray[g_iFrameTimeIndex] = fFrameTime;
    g_iFrameTimeIndex = (g_iFrameTimeIndex + 1) % FRAME_TIME_ARRAY_SIZE;
    g_iFramesProcessed++;

    if (g_iFramesProcessed % 1000 == 0 && g_hCvarEnable1000Ticks.BoolValue)
    {
        LogFrameTimeDeviation1000Ticks();
        PrintToServer("Profiling ticks remaining: %d", g_iProfilingTicks - 1);
    }

    else if (g_iFramesProcessed % 100 == 0 && g_iFramesProcessed % 1000 != 0 && g_hCvarEnable100Ticks.BoolValue)
    {
        LogFrameTimeDeviation100Ticks();
        PrintToServer("Profiling ticks remaining: %d", g_iProfilingTicks - 1);
    }

    else if (g_iFramesProcessed % 10 == 0 && g_iFramesProcessed % 100 != 0 && g_hCvarEnable10Ticks.BoolValue)
    {
        LogFrameTimeDeviation10Ticks();
    }


    if (g_hCvarEnableFrameTimes.BoolValue)
    {
        LogFrameTimesPerTick(fFrameTime);
    }

    g_iProfilingTicks--;

    if (g_iProfilingTicks <= 0)
    {
        PrintToServer("Profiling ticks reached zero. Stopping profiling.");
        StopProfiling();
    }
}

void LogFrameTimesPerTick(float fFrameTime)
{
    if (g_hCvarEnableFrameTimes.BoolValue)
    {
        char sFrameTime[BUFFER_SIZE];
        FormatEx(sFrameTime, sizeof(sFrameTime), "[%.6f] %.6f", GetEngineTime(), fFrameTime);
        WriteFileString(g_hFileFrameTimes, sFrameTime, false);
        WriteFileString(g_hFileFrameTimes, "\n", false);
    }
}

void LogFrameTimeDeviation10Ticks()
{
    if (g_iFramesProcessed % 10 == 0 && g_hCvarEnable10Ticks.BoolValue)
    {
        float fAverageFrameTime = CalculateAverageFrameTime(10);
        float fStandardDeviation = CalculateStandardDeviation(10, fAverageFrameTime);
        LogFrameTimeToFile(g_hFile10Ticks, 10, fAverageFrameTime, fStandardDeviation);
    }
}

void LogFrameTimeDeviation100Ticks()
{
    if (g_iFramesProcessed % 100 == 0 && g_hCvarEnable100Ticks.BoolValue)
    {
        PrintToServer("Logging frame time deviation for 100 ticks.");
        float fAverageFrameTime = CalculateAverageFrameTime(100);
        float fStandardDeviation = CalculateStandardDeviation(100, fAverageFrameTime);
        LogFrameTimeToFile(g_hFile100Ticks, 100, fAverageFrameTime, fStandardDeviation);
    }
}

void LogFrameTimeDeviation1000Ticks()
{
    if (g_iFramesProcessed % 1000 == 0 && g_hCvarEnable1000Ticks.BoolValue)
    {
        PrintToServer("Logging frame time deviation for 1000 ticks.");
        float fAverageFrameTime = CalculateAverageFrameTime(1000);
        float fStandardDeviation = CalculateStandardDeviation(1000, fAverageFrameTime);
        LogFrameTimeToFile(g_hFile1000Ticks, 1000, fAverageFrameTime, fStandardDeviation);
    }
}

float CalculateAverageFrameTime(int iTicks)
{
    float fTotalFrameTime = 0.0;
    for (int i = 0; i < iTicks; i++)
    {
        int iIndex = (g_iFrameTimeIndex - iTicks + i + FRAME_TIME_ARRAY_SIZE) % FRAME_TIME_ARRAY_SIZE;
        fTotalFrameTime += g_fFrameTimeArray[iIndex];
    }
    return fTotalFrameTime / float(iTicks);
}

float CalculateStandardDeviation(int iTicks, float fAverageFrameTime)
{
    float fVariance = 0.0;
    for (int i = 0; i < iTicks; i++)
    {
        int iIndex = (g_iFrameTimeIndex - iTicks + i + FRAME_TIME_ARRAY_SIZE) % FRAME_TIME_ARRAY_SIZE;
        float fDiff = g_fFrameTimeArray[iIndex] - fAverageFrameTime;
        fVariance += fDiff * fDiff;
    }
    fVariance /= float(iTicks - 1); 
    return SquareRoot(fVariance);
}

void LogFrameTimeToFile(File hFile, int iTicks, float fAverageFrameTime, float fStandardDeviation)
{
    if (hFile == null)
    {
        PrintToServer("Invalid file handle for logging frame time deviation (%d ticks).", iTicks);
        return;
    }

    char sBuffer[BUFFER_SIZE];
    FormatEx(sBuffer, sizeof(sBuffer), "Average Frame Time (%d Ticks): %.6f", iTicks, fAverageFrameTime);
    WriteFileString(hFile, sBuffer, false);
    WriteFileString(hFile, "\n", false);
    FormatEx(sBuffer, sizeof(sBuffer), "Frame Time Standard Deviation (%d Ticks): %.6f", iTicks, fStandardDeviation);
    WriteFileString(hFile, sBuffer, false);
    WriteFileString(hFile, "\n\n", false);
}

void CreateLogDirectory()
{
    char sFilePath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "logs/frametime");
    if (!DirExists(sFilePath))
    {
        if (CreateDirectory(sFilePath, 511))
        {
            PrintToServer("Created directory: %s", sFilePath);
        }
        else
        {
            LogError("Failed to create directory: %s", sFilePath);
        }
    }
}

bool CreateLogFiles()
{
    char sFilePath[PLATFORM_MAX_PATH];
    bool bSuccess = true;

    // Debugging log for directory creation
    PrintToServer("Creating log files...");

    if (g_hCvarEnable10Ticks.BoolValue)
    {
        BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "logs/frametime/frametime_%s_10_ticks.log", g_sProfilingPrefix);
        g_hFile10Ticks = OpenFile(sFilePath, "a");
        if (g_hFile10Ticks == null)
        {
            LogError("Failed to open log file for 10 ticks: %s", sFilePath);
            bSuccess = false;
        }
        else
        {
            PrintToServer("Opened file for 10 ticks logging: %s", sFilePath);
        }
    }

    if (g_hCvarEnable100Ticks.BoolValue)
    {
        BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "logs/frametime/frametime_%s_100_ticks.log", g_sProfilingPrefix);
        g_hFile100Ticks = OpenFile(sFilePath, "a");
        if (g_hFile100Ticks == null)
        {
            LogError("Failed to open log file for 100 ticks: %s", sFilePath);
            bSuccess = false;
        }
        else
        {
            PrintToServer("Opened file for 100 ticks logging: %s", sFilePath);
        }
    }

    if (g_hCvarEnable1000Ticks.BoolValue)
    {
        BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "logs/frametime/frametime_%s_1000_ticks.log", g_sProfilingPrefix);
        g_hFile1000Ticks = OpenFile(sFilePath, "a");
        if (g_hFile1000Ticks == null)
        {
            LogError("Failed to open log file for 1000 ticks: %s", sFilePath);
            bSuccess = false;
        }
        else
        {
            PrintToServer("Opened file for 1000 ticks logging: %s", sFilePath);
        }
    }

    if (g_hCvarEnableFrameTimes.BoolValue)
    {
        BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "logs/frametime/frametime_%s_per_tick.log", g_sProfilingPrefix);
        g_hFileFrameTimes = OpenFile(sFilePath, "a");
        if (g_hFileFrameTimes == null)
        {
            LogError("Failed to open log file for per-tick frame times: %s", sFilePath);
            bSuccess = false;
        }
    }

    return bSuccess;
}

void CloseLogFiles()
{
    if (g_hFile10Ticks != null)
    {
        CloseHandle(g_hFile10Ticks);
        g_hFile10Ticks = null;
    }

    if (g_hFile100Ticks != null)
    {
        CloseHandle(g_hFile100Ticks);
        g_hFile100Ticks = null;
    }

    if (g_hFile1000Ticks != null)
    {
        CloseHandle(g_hFile1000Ticks);
        g_hFile1000Ticks = null;
    }

    if (g_hFileFrameTimes != null)
    {
        CloseHandle(g_hFileFrameTimes);
        g_hFileFrameTimes = null;
    }
}
