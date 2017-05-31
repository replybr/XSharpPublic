//
// Copyright (c) XSharp B.V.  All Rights Reserved.  
// Licensed under the Apache License, Version 2.0.  
// See License.txt in the project root for license information.
//

BEGIN NAMESPACE XSharp.RDD 
ENUM DbLockMode
	MEMBER @@Lock
	MEMBER UnLock
END ENUM

ENUM DbRecordInfo
	MEMBER Deleted 	:= DBRI_DELETED 
	MEMBER Locked 	:= DBRI_LOCKED 	
	MEMBER RecSize 	:= DBRI_RECSIZE	
	MEMBER Recno 	:= DBRI_RECNO	
	MEMBER Updated 	:= DBRI_UPDATED	
	MEMBER BuffPtr 	:= DBRI_BUFFPTR 
	MEMBER User 	:= DBRI_USER	
END ENUM

ENUM DbFieldInfo
	MEMBER Name					:= DBS_NAME	
	MEMBER Type					:= DBS_TYPE	
	MEMBER Len					:= DBS_LEN		
	MEMBER Dec					:= DBS_DEC		
	MEMBER Alias				:= DBS_ALIAS
	MEMBER Blob_Get	            := DBS_BLOB_GET
	MEMBER Blob_Type			:= DBS_BLOB_TYPE		
	MEMBER Blob_Len				:= DBS_BLOB_LEN			
	MEMBER Blob_OffSet			:= DBS_BLOB_OFFSET
	MEMBER BLOB_Pointer			:= DBS_BLOB_POINTER		
	MEMBER Blob_Direct_Type		:= DBS_BLOB_DIRECT_TYPE
	MEMBER Blob_Direct_Len		:= DBS_BLOB_DIRECT_LEN			
	MEMBER Struct_				:= DBS_STRUCT				
	MEMBER Properties			:= DBS_PROPERTIES
	MEMBER User					:= DBS_USER		
	MEMBER IsNull               := DBS_ISNULL
	MEMBER Counter          	:= DBS_COUNTER
	MEMBER @@Step             	:= DBS_STEP
END ENUM             

ENUM DbInfo
	MEMBER ISDBF 		:= DBI_ISDBF
	MEMBER CANPUTREC := DBI_CANPUTREC
	MEMBER GETHEADERSIZE := DBI_GETHEADERSIZE
	MEMBER LASTUPDATE := DBI_LASTUPDATE
	MEMBER GETDELIMITER := DBI_GETDELIMITER
	MEMBER SETDELIMITER := DBI_SETDELIMITER 
	MEMBER GETRECSIZE := DBI_GETRECSIZE
	MEMBER GETLOCKARRAY := DBI_GETLOCKARRAY
	MEMBER TABLEEXT := DBI_TABLEEXT
	MEMBER READONLY := DBI_READONLY 
	MEMBER ISFLOCK := DBI_ISFLOCK
	MEMBER CHILDCOUNT := DBI_CHILDCOUNT 
	MEMBER FILEHANDLE := DBI_FILEHANDLE 
	MEMBER FULLPATH := DBI_FULLPATH 
	MEMBER ISANSI := DBI_ISANSI 
	MEMBER BOF := DBI_BOF 
	MEMBER EOF := DBI_EOF 
	MEMBER DBFILTER := DBI_DBFILTER
	MEMBER FOUND := DBI_FOUND 
	MEMBER FCOUNT := DBI_FCOUNT
	MEMBER LOCKCOUNT := DBI_LOCKCOUNT
	MEMBER VALIDBUFFER  := DBI_VALIDBUFFER 
	MEMBER ALIAS := DBI_ALIAS
	MEMBER GETSCOPE := DBI_GETSCOPE
	MEMBER LOCKOFFSET := DBI_LOCKOFFSET
	MEMBER SHARED := DBI_SHARED
	MEMBER MEMOEXT := DBI_MEMOEXT
	MEMBER MEMOHANDLE := DBI_MEMOHANDLE
	MEMBER BLOB_HANDLE := DBI_BLOB_HANDLE
	MEMBER MEMOBLOCKSIZE := DBI_MEMOBLOCKSIZE
	MEMBER BLOB_INTEGRITY := DBI_BLOB_INTEGRITY
	MEMBER CODEPAGE := DBI_CODEPAGE
	MEMBER BLOB_RECOVER := DBI_BLOB_RECOVER
	MEMBER NEWINDEXLOCK := DBI_NEWINDEXLOCK
	MEMBER DB_VERSION := DBI_DB_VERSION
	MEMBER RDD_VERSION := DBI_RDD_VERSION
	MEMBER RDD_LIST := DBI_RDD_LIST
	MEMBER MEMOFIELD := DBI_MEMOFIELD
	MEMBER VO_MACRO_SYNTAX := DBI_VO_MACRO_SYNTAX
	MEMBER RDD_OBJECT := DBI_RDD_OBJECT
	MEMBER USER 		:=  DBI_USER 		
	MEMBER RL_AND 		:= DBI_RL_AND 		
	MEMBER RL_CLEAR 	:= DBI_RL_CLEAR 	
	MEMBER RL_COUNT 	:= DBI_RL_COUNT 	
	MEMBER RL_DESTROY 	:= DBI_RL_DESTROY 	
	MEMBER RL_EXFILTER 	:= DBI_RL_EXFILTER 	
	MEMBER RL_GETFILTER := DBI_RL_GETFILTER 
	MEMBER RL_HASMAYBE 	:= DBI_RL_HASMAYBE 
	MEMBER RL_LEN 		:= DBI_RL_LEN 	
	MEMBER RL_MAYBEEVAL := DBI_RL_MAYBEEVAL
	MEMBER RL_NEW 		:= DBI_RL_NEW 	
	MEMBER RL_NEWDUP 	:= DBI_RL_NEWDUP 
	MEMBER RL_NEWQUERY 	:= DBI_RL_NEWQUERY 
	MEMBER RL_NEXTRECNO := DBI_RL_NEXTRECNO
	MEMBER RL_NOT 		:= DBI_RL_NOT 	
	MEMBER RL_OR 		:= DBI_RL_OR 	
	MEMBER RL_PREVRECNO := DBI_RL_PREVRECNO
	MEMBER RL_SET 		:= DBI_RL_SET 	
	MEMBER RL_SETFILTER := DBI_RL_SETFILTER
	MEMBER RL_TEST 		:= DBI_RL_TEST 	
                            
END ENUM

END NAMESPACE

ENUM DbFieldType
	MEMBER @@Character 	:= 67 	// 'C', uses len and dec
	MEMBER @@Date	 	:= 68 	// 'D', 8 bytes
	MEMBER @@Logic   	:= 76  	// 'L', 1 byte
	MEMBER @@Memo    	:= 77  	// 'M', 4 or 10 bytes see Length
	MEMBER @@Number    	:= 78  	// 'N', uses len and dec
	MEMBER @@VOObject	:= 79  	// 'O'
	MEMBER @@Unknown	:= 0	//                                  
	
//	MEMBER @@Double     := 66  	// 'B'	FOX Type, also '8'
//	MEMBER @@Currency	:= 89  	// 'Y'	8 byte FOX Type
//	MEMBER @@DateTime	:= 84  	// 'T'	FOX Type can be 4 or 8 bytes
//	MEMBER @@Float		:= 70  	// 'F'	FOX Type, uses len and dec
//	MEMBER @@Integer	:= 73  	// 'I'	FOX Type , autoInc
//	MEMBER @@Picture	:= 80  	// 'P'	FOX Type, 4 or 10 bytes
//	MEMBER @@CurrencyDouble	:= 90  	// 'Z'	8 byte Currency
//	MEMBER @@Integer2	:= 50  	// '2'	2 byte int, autoInc
//	MEMBER @@Integer4	:= 52  	// '4'	4 byte int, autoInc
//	MEMBER @@Double8	:= 56	// '8' Same as 'B'
	// '@' = Timestamp 8 bytes
	// '=' = ModTime, 8 bytes
	// '^' = RowVer, 8 bytes  
	// '+' = AutoInc, 4 bytes
	// 'Q' = VarLenghth , between 1 and 255 
	// 'V' = VarLength
	// 'W' = Blob 4 or 10 bytes
	// 'G' = Ole 4 or 10 bytes
END ENUM



USING System
INTERNAL ENUM DbfHeaderCodepage AS BYTE
    MEMBER CP_DBF_DOS_OLD:=0
    MEMBER CP_DBF_DOS_US:=1
    MEMBER CP_DBF_DOS_INTL:=2
    MEMBER CP_DBF_WIN_ANSI:=3
    MEMBER CP_DBF_MAC_STANDARD:=4
    MEMBER CP_DBF_DOS_EEUROPEAN:=100
    MEMBER CP_DBF_DOS_RUSSIAN:=101
    MEMBER CP_DBF_DOS_NORDIC:=102
    MEMBER CP_DBF_DOS_ICELANDIC:=103
    MEMBER CP_DBF_DOS_KAMENICKY:=104
    MEMBER CP_DBF_DOS_MAZOVIA:=105
    MEMBER CP_DBF_DOS_GREEK:=106
    MEMBER CP_DBF_DOS_TURKISH:=107
    MEMBER CP_DBF_DOS_CANADIAN:=108
    MEMBER CP_DBF_WIN_CHINESE_1:=120
    MEMBER CP_DBF_WIN_KOREAN:=121
    MEMBER CP_DBF_WIN_CHINESE_2:=122
    MEMBER CP_DBF_WIN_JAPANESE:=123
    MEMBER CP_DBF_WIN_THAI:=124
    MEMBER CP_DBF_WIN_HEBREW:=125
    MEMBER CP_DBF_WIN_ARABIC:=126
    MEMBER CP_DBF_MAC_RUSSIAN:=150
    MEMBER CP_DBF_MAC_EEUROPEAN:=151
    MEMBER CP_DBF_MAC_GREEK:=152
    MEMBER CP_DBF_WIN_EEUROPEAN:=200
    MEMBER CP_DBF_WIN_RUSSIAN:=201
    MEMBER CP_DBF_WIN_TURKISH:=202
    MEMBER CP_DBF_WIN_GREEK:=203
END ENUM

