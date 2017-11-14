char currentMap[128];
char currentUrl[256];

void MAP_OnAllPluginLoaded()
{
    RegAdminCmd("sm_updatemap", Command_UpdateMap, ADMFLAG_BAN);
    RegAdminCmd("sm_deletemap", Command_DeleteMap, ADMFLAG_BAN);
    CreateTimer(1800.0, Timer_CheckUpdateMap, _, TIMER_REPEAT);
}

public void SQLCallback_CheckMap(Handle owner, Handle hndl, const char[] error, int startCheck)
{
    if(hndl == INVALID_HANDLE)
    {
        LogError("Can not get map list from database :  %s", error);
        return;
    }
    
    if(SQL_GetRowCount(hndl) < 1)
    {
        LogError("Can not get map list from database!");
        return;
    }

    LogMessage("Syncing Map from database!");

    char map[128];

    ArrayList array_mapmysql = CreateArray(ByteCountToCells(128));
    while(SQL_FetchRow(hndl))
    {
        SQL_FetchString(hndl, 0,  map, 128);
        PushArrayString(array_mapmysql, map);
    }
    
    if(startCheck == 0)
        CheckMapsOnStart(array_mapmysql);
    else
        CheckMapsOnDelete(array_mapmysql, startCheck);

    delete array_mapmysql;
}

void CheckMapsOnStart(ArrayList array_mapmysql)
{
    ArrayList array_maplocal = CreateArray(ByteCountToCells(128));
    int mapListSerial = -1;
    if(ReadMapList(array_maplocal, mapListSerial, "default", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_NO_DEFAULT) == INVALID_HANDLE)
        if(mapListSerial == -1)
            return;
        
    int arraysize_maplocal = GetArraySize(array_maplocal);
    
    bool deleted;
    
    char map[128];
    
    for(int index = 0; index < arraysize_maplocal; ++index)
    {
        GetArrayString(array_maplocal, index, map, 128);
        
        if(strlen(map) < 3) continue;
        
        if(FindStringInArray(array_mapmysql, map) != -1) continue;
        
        Format(map, 128, "maps/%s.bsp", map);
        
        LogMessage("Delete %s %s!", map, DeleteFile(map) ? "successful" : "failed");
        
        deleted = true;
    }
    
    delete array_maplocal; 

    if(deleted)
    {
        CreateTimer(1.0, Timer_ChangeMap);
        CreateTimer(9.9, Timer_RestartSV);
    }
}

public Action Timer_ChangeMap(Handle timer)
{
    switch(CG_GetServerId())
    {
        case 1, 2, 3, 4: ForceChangeLevel("ze_", "restart");
        case 5, 6      : ForceChangeLevel("tt_", "restart");
        case 7         : ForceChangeLevel("mg_", "restart");
        case 8, 9      : ForceChangeLevel("jb_", "restart");
        case 11        : ForceChangeLevel("hg_", "restart");
        case 12        : ForceChangeLevel("ds_", "restart");
        case 15, 16    : ForceChangeLevel("kz_", "restart");
    }
    return Plugin_Stop;
}

public Action Timer_RestartSV(Handle timer)
{
    ServerCommand("exit");
    return Plugin_Stop;
}

public Action Timer_CheckUpdateMap(Handle timer)
{
    CheckingNewMap();
    return Plugin_Continue;
}

void CheckingNewMap()
{
    char m_szQuery[128];
    Format(m_szQuery, 128, "SELECT `id`, `map` FROM `map_update` WHERE `sid` = '%d' AND `done` = '0' AND `try` < '3' ORDER BY id ASC LIMIT 1", CG_GetServerId());
    SQL_TQuery(g_hDatabase, SQLCallback_GetNewMap, m_szQuery);

    PrintToServer("Checking new map from databases");
}

public void SQLCallback_GetNewMap(Handle owner, Handle hndl, const char[] error, any unuse)
{
    if(owner == INVALID_HANDLE || hndl == INVALID_HANDLE)
    {
        LogError("Checking new map list failed: %s", error);
        return;
    }
    
    if(!SQL_FetchRow(hndl))
    {
        PrintToServer("no new map from database");
        return;
    }

    SQL_FetchString(hndl, 1, currentMap, 128);
    
    Format(currentUrl, 256, "https://maps.csgogamers.com/%s.bsp.bz2", currentMap);

    if(currentMap[0] == '\0' || strlen(currentUrl) <= 35)
    {
        PrintToServer("invalid map from database");
        return;
    }

    char path[256];
    Format(path, 256, "addons/sourcemod/data/download/%s.bsp.bz2", currentMap);
    System2_DownloadFile(MAP_OnDownloadMapCompleted, currentUrl, path);

    char m_szQuery[128];
    Format(m_szQuery, 128, "UPDATE map_update SET try=try+1 WHERE id=%d", SQL_FetchInt(hndl, 0));
    CG_DatabaseSaveGames(m_szQuery);
    
    PrintToServer("Download %s from %s", currentMap, currentUrl);
}

public void MAP_OnDownloadMapCompleted(bool finished, const char[] error, float dltotal, float dlnow, float ultotal, float ulnow)
{
    PrintToServer("[%.2f%%] Downloading %s.bsp.bz2 ", (dlnow/dltotal)*100, currentMap);

    if(finished)
    {
        if(!StrEqual(error, ""))
        {
            LogError("Download %s.bsp.bz2 form %s failed: %s", currentMap, currentUrl, error);
            char path[256];
            Format(path, 256, "addons/sourcemod/data/download/%s.bsp.bz2", currentMap);
            DeleteFile(path);
            
            currentMap[0] = '\0';
            currentUrl[0] = '\0';
        
            CheckingNewMap();

            return;
        }

        char path[256];
        Format(path, 256, "addons/sourcemod/data/download/%s.bsp.bz2", currentMap);
        System2_ExtractArchive(MAP_OnBz2ExtractCompleted, path, "addons/sourcemod/data/download/");
        
        PrintToServer("ExtractArchive %s to addons/sourcemod/data/download/%s.bsp", path, currentMap);
    }
}

public void MAP_OnBz2ExtractCompleted(const char[] output, const int size, CMDReturn status)
{
    if(status == CMD_SUCCESS)
    {
        char path[256], maps[256];
        Format(path, 256, "addons/sourcemod/data/download/%s.bsp", currentMap);
        Format(maps, 256, "maps/%s.bsp", currentMap);

        System2_CopyFile(MAP_OnMapCopyCompleted, path, maps);
        
        PrintToServer("Copy %s to %s", path, maps);
    }
    else if(status == CMD_ERROR)
    {
        LogError("Bz2 Extract addons/sourcemod/data/download/%s.bsp.bz2 failed: \n%s", currentMap, output);

        char path[256];
        Format(path, 256, "addons/sourcemod/data/download/%s.bsp.bz2", currentMap);
        DeleteFile(path);
        
        currentMap[0] = '\0';
        currentUrl[0] = '\0';
        
        CheckingNewMap();
    }
}

public void MAP_OnMapCopyCompleted(bool success, const char[] from, const char[] to)
{
    if(success)
    {
        if(!IsMapValid(currentMap))
        {
            DeleteFile(to);
            LogError("Validate %s failed!",  currentMap);
        }

        char del[256];

        Format(del, 256, "addons/sourcemod/data/download/%s.bsp.bz2", currentMap);
        if(!DeleteFile(del))
            LogError("Delete %s failed.",  del);

        Format(del, 256, "addons/sourcemod/data/download/%s.bsp", currentMap);
        if(!DeleteFile(del))
            LogError("Delete %s failed.",  del);
        
        UpdateMapStatus();
        CheckingNewMap();
        
        PrintToServer("Add new map %s successful!", currentMap);
    }
}

void UpdateMapStatus()
{
    char m_szQuery[256], emap[128];
    SQL_EscapeString(g_hDatabase, currentMap, emap, 128);
    Format(m_szQuery, 512, "UPDATE map_update SET done = 1 WHERE sid = %d AND map = '%s'", CG_GetServerId(), emap);
    CG_DatabaseSaveGames(m_szQuery);
    
    currentMap[0] = '\0';
    currentUrl[0] = '\0';
}

public Action Command_UpdateMap(int client, int args)
{
    CheckingNewMap();

    return Plugin_Handled;
}

public Action Command_DeleteMap(int client, int args)
{
    char auth[32];
    GetClientAuthId(client, AuthId_Steam2, auth, 32, true);
    
    AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, auth);
    
    if(admin == INVALID_ADMIN_ID)
        return Plugin_Handled;
    
    if(GetAdminImmunityLevel(admin) < 50)
        return Plugin_Handled;

    switch(CG_GetServerId())
    {
        case 1, 2, 3, 4 : SQL_TQuery(g_hDatabase, SQLCallback_CheckMap, "SELECT `map` FROM map_database WHERE `mod` = 'ze'", client);
        case 5, 6       : SQL_TQuery(g_hDatabase, SQLCallback_CheckMap, "SELECT `map` FROM map_database WHERE `mod` = 'tt'", client);
        case 7          : SQL_TQuery(g_hDatabase, SQLCallback_CheckMap, "SELECT `map` FROM map_database WHERE `mod` = 'mg'", client);
        case 8, 9       : SQL_TQuery(g_hDatabase, SQLCallback_CheckMap, "SELECT `map` FROM map_database WHERE `mod` = 'jb'", client);
        case 11         : SQL_TQuery(g_hDatabase, SQLCallback_CheckMap, "SELECT `map` FROM map_database WHERE `mod` = 'hg'", client);
        case 12         : SQL_TQuery(g_hDatabase, SQLCallback_CheckMap, "SELECT `map` FROM map_database WHERE `mod` = 'ds'", client);
        case 15,16,19,20: SQL_TQuery(g_hDatabase, SQLCallback_CheckMap, "SELECT `map` FROM map_database WHERE `mod` = 'kz'", client);
    }

    return Plugin_Handled;
}

void CheckMapsOnDelete(ArrayList array_mapmysql, int client)
{
    if(!IsClientInGame(client))
        return;
    
    char auth[32];
    GetClientAuthId(client, AuthId_Steam2, auth, 32, true);
    
    AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, auth);
    
    if(admin == INVALID_ADMIN_ID)
        return;
    
    if(GetAdminImmunityLevel(admin) < 50)
        return;
    
    Handle menu = CreateMenu(MenuHandler_DeleteMap);
    SetMenuTitle(menu, "Delete map menu");
    
    char map[128];
    int array_size = GetArraySize(array_mapmysql);
    for(int index = 0; index < array_size; ++index)
    {
        GetArrayString(array_mapmysql, index, map, 128);
        AddMenuItem(menu, map, map);
    }

    DisplayMenu(menu, client, 0);
}

public int MenuHandler_DeleteMap(Handle menu, MenuAction action, int client, int param2)
{
    switch(action)
    {
        case MenuAction_End: CloseHandle(menu);
        case MenuAction_Select:
        {
            char info[128];
            GetMenuItem(menu, param2, info, 128);
            BuildConfirmMenu(client, info);
        }
    }
}

void BuildConfirmMenu(int client, const char[] info)
{
    Handle menu = CreateMenu(MenuHandler_Confirm);
    SetMenuTitle(menu, "Confirm delete? \n-> %s", info);
    SetMenuExitButton(menu, false);

    AddMenuItem(menu, " ", " ", ITEMDRAW_SPACER);
    AddMenuItem(menu, " ", " ", ITEMDRAW_SPACER);
    AddMenuItem(menu, " ", " ", ITEMDRAW_SPACER);
    AddMenuItem(menu, " ", " ", ITEMDRAW_SPACER);

    AddMenuItem(menu, info, "sure");
    AddMenuItem(menu, "no", "exit");
    
    DisplayMenu(menu, client, 0);
}

public int MenuHandler_Confirm(Handle menu, MenuAction action, int client, int param2)
{
    switch(action)
    {
        case MenuAction_End: CloseHandle(menu);
        case MenuAction_Select:
        {
            char info[128];
            GetMenuItem(menu, param2, info, 128);
            if(StrEqual(info, "no"))
                return;

            UTIL_DeleteMap(client, info);
        }
    }
}

void UTIL_DeleteMap(int client, const char[] map)
{
    char m_szQuery[256];
    Format(m_szQuery, 256, "DELETE FROM map_database WHERE map = '%s'", map);
    CG_DatabaseSaveGames(m_szQuery);
    
    PrintToChat(client, "[\x07MAP\x01]  已从数据库中删除该地图.");
    PrintToChat(client, "[\x07MAP\x01]  当前服务器将在下次启动时,从本地删除地图.");
}