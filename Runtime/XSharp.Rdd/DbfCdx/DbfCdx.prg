//
// Copyright (c) XSharp B.V.  All Rights Reserved.  
// Licensed under the Apache License, Version 2.0.  
// See License.txt in the project root for license information.
//

USING XSharp.RDD.Support
USING XSharp.RDD.CDX
USING XSharp.RDD.Enums
USING System.IO
USING System.Diagnostics

#ifdef TESTCDX
    GLOBAL LOGGING := FALSE AS LOGIC
    GLOBAL VALIDATETREE := FALSE AS LOGIC
    
#endif

BEGIN NAMESPACE XSharp.RDD
    // Inherits all standard DBF and Memo behavior
    // Only adds Order Handling
    /// <summary>DBFCDX RDD. For DBF/FPT/CDX.</summary>
    [DebuggerDisplay("DBFCDX ({Alias,nq})")];
    CLASS DBFCDX INHERIT DBFFPT
        INTERNAL _indexList  AS CdxOrderBagList
        INTERNAL PROPERTY CurrentOrder AS CdxTag GET _indexList:CurrentOrder
        VIRTUAL PROPERTY Driver  AS STRING GET "DBFCDX"
        
        
        CONSTRUCTOR()
            SUPER()
            _indexList := CdxOrderBagList{SELF}
            RETURN
            
            
            #ifdef TESTCDX
            PUBLIC STATIC METHOD StartLogging AS VOID
                LOGGING := TRUE
                RETURN 
                
            PUBLIC STATIC METHOD StopLogging AS VOID
                LOGGING := FALSE
                RETURN 
                
            PUBLIC STATIC METHOD ValidateTree AS VOID
                VALIDATETREE := TRUE
                CoreDb.GoTop()
                VALIDATETREE := FALSE
                RETURN 
            #endif
            
            
            
            #region Order Support
            
            VIRTUAL METHOD OrderCreate(orderInfo AS DbOrderCreateInfo ) AS LOGIC
                VAR useMemoryStream := FSize(SELF:_hFile) < Int32.MaxValue .AND. ! SELF:_Shared
                IF useMemoryStream
                    FConvertToMemoryStream(SELF:_hFile)
                ENDIF
                VAR result := SELF:_indexList:Create(orderInfo)
                IF useMemoryStream
                    FConvertToFileStream(SELF:_hFile)
                ENDIF
                RETURN result
                
            VIRTUAL METHOD OrderDestroy(orderInfo AS DbOrderInfo ) AS LOGIC
                RETURN SELF:_indexList:Destroy(orderInfo)
                
            METHOD OrderCondition(info AS DbOrderCondInfo) AS LOGIC
                RETURN SUPER:OrderCondition(info)
                
            VIRTUAL METHOD OrderListAdd( orderInfo AS DbOrderInfo) AS LOGIC
                BEGIN LOCK SELF
                    SELF:GoCold()
                    LOCAL fullPath AS STRING
                    fullPath := orderInfo:BagName
                    IF File(fullPath)
                        fullPath := FPathName()
                    ELSEIF String.IsNullOrEmpty(Path.GetExtension(fullPath)) 
                        fullPath := Path.ChangeExtension(fullPath, CdxOrderBag.CDX_EXTENSION)
                        IF File(fullPath)
                            fullPath := FPathName()
                            orderInfo:BagName := fullPath
                        ENDIF
                    ENDIF
                    IF String.IsNullOrEmpty(System.IO.Path.GetDirectoryName(fullPath))
                        fullPath := System.IO.Path.Combine(System.IO.Path.GetDirectoryName(SELF:_FileName), fullPath)
                        orderInfo:BagName := fullPath
                    ENDIF
                    LOCAL lOk := FALSE AS LOGIC
                    IF SELF:_indexList:FindOrderBag(orderInfo:BagName) == NULL
                        lOk := SELF:_indexList:Add(orderInfo)
                    ELSE
                        // Already open, do nothing
                        lOk := TRUE
                    ENDIF
                    IF lOk
                        orderInfo:Order := 1
                        lOk := SELF:OrderListFocus(orderInfo)
                    ENDIF
                    RETURN lOk
                END LOCK
                
            
            METHOD _CloseAllIndexes(orderInfo AS DbOrderInfo, lCloseStructural AS LOGIC) AS LOGIC
                RETURN SELF:_indexList:Delete(orderInfo, lCloseStructural)
                
            VIRTUAL METHOD OrderListDelete(orderInfo AS DbOrderInfo) AS LOGIC
                BEGIN LOCK SELF
                    SELF:GoCold()
                    RETURN SELF:_CloseAllIndexes(orderInfo, FALSE)
                END LOCK
            
            VIRTUAL METHOD OrderListFocus(orderInfo AS DbOrderInfo) AS LOGIC
                BEGIN LOCK SELF
                    SELF:GoCold()
                    RETURN SELF:_indexList:Focus(orderInfo)
                END LOCK
            
            VIRTUAL METHOD OrderListRebuild() AS LOGIC
                BEGIN LOCK SELF
                    IF SELF:Shared 
                        // Error !! Cannot be written !
                        SELF:_dbfError( ERDD.SHARED, XSharp.Gencode.EG_SHARED )
                        RETURN FALSE
                    ENDIF
                    IF SELF:_ReadOnly
                        SELF:_dbfError( ERDD.READONLY, XSharp.Gencode.EG_READONLY)
                        RETURN FALSE
                    ENDIF
                    
                    SELF:GoCold()
                    RETURN SELF:_indexList:Rebuild()
                END LOCK
            
            OVERRIDE METHOD OrderInfo(nOrdinal AS DWORD , info AS DbOrderInfo ) AS OBJECT
                LOCAL result AS LONG
                LOCAL isOk := FALSE AS LOGIC
                
                result := 0
                SELF:_indexList:FindOrder(info, OUT VAR workOrder)

                IF workOrder == NULL .AND. info:IsEmpty
                    workOrder := SELF:CurrentOrder
                ENDIF
                
                BEGIN SWITCH nOrdinal
                CASE DBOI_CONDITION
                    IF workOrder != NULL
                        info:Result := workOrder:Condition
                    ENDIF
                CASE DBOI_EXPRESSION
                    IF workOrder != NULL
                        info:Result := workOrder:Expression
                    ENDIF
                CASE DBOI_ORDERCOUNT
                    info:Result := SELF:_indexList:Count
                CASE DBOI_POSITION
                    IF workOrder == NULL
                        info:Result := SELF:RecNo
                    ELSE
                        isOk := workOrder:_getRecPos( REF result)
                        IF isOk
                            info:Result := result
                        ENDIF
                    ENDIF
                CASE DBOI_KEYCOUNT
                    result := 0
                    IF workOrder != NULL
                        info:Result := 0
                        isOk := workOrder:_CountRecords(REF result)
                    ELSE
                        isOk := TRUE
                    ENDIF
                    IF isOk
                        info:Result := result
                    ENDIF
                CASE DBOI_NUMBER
                    info:Result := SELF:_indexList:OrderPos(workOrder)
                CASE DBOI_BAGEXT
                    // according to the docs this should always return the default extension and not the actual extension
                    info:Result := CdxOrderBag.CDX_EXTENSION
                CASE DBOI_FULLPATH
                    IF workOrder != NULL
                        info:Result := workOrder:OrderBag:FullPath
                    ELSE
                        info:Result := ""
                    ENDIF
                CASE DBOI_BAGNAME
                    //CASE DBOI_INDEXNAME // alias
                    IF workOrder != NULL
                        info:Result := workOrder:FileName
                    ELSE
                        info:Result := ""
                    ENDIF
                CASE DBOI_NAME
                    IF workOrder != NULL
                        info:Result := workOrder:_orderName
                    ELSE
                        info:Result := ""
                    ENDIF
                CASE DBOI_COLLATION
                     info:Result := ""
                     IF workOrder != NULL
                        LOCAL collation as VfpCollation
                        collation := workOrder:Collation
                        if collation  != NULL
                            info:Result := collation:Name
                        ENDIF
                    ENDIF

                CASE DBOI_FILEHANDLE
                    IF workOrder != NULL
                        info:Result := workOrder:OrderBag:Handle
                    ELSE
                        info:Result := IntPtr.Zero
                    ENDIF
                CASE DBOI_ISDESC
                    IF workOrder != NULL
                        VAR oldValue  := workOrder:Descending
                        IF info:Result IS LOGIC VAR descend
                            workOrder:Descending := descend
                        ENDIF
                        info:Result := oldValue
                    ELSE
                        info:Result := FALSE
                    ENDIF
                CASE DBOI_ISCOND
                    IF workOrder != NULL
                        info:Result := workOrder:Conditional
                    ELSE
                        info:Result := FALSE
                    ENDIF
                CASE DBOI_KEYTYPE
                    IF workOrder != NULL
                        info:Result := workOrder:KeyType
                    ELSE
                        info:Result := 0
                    ENDIF
                CASE DBOI_KEYSIZE
                    IF workOrder != NULL
                        info:Result := workOrder:KeyLength
                    ELSE
                        info:Result := 0
                    ENDIF
                CASE DBOI_KEYDEC
                    info:Result := 0
                CASE DBOI_HPLOCKING
                    info:Result := FALSE
                CASE DBOI_UNIQUE
                    IF workOrder != NULL
                        info:Result := workOrder:Unique
                    ELSE
                        info:Result := FALSE
                    ENDIF
                CASE DBOI_LOCKOFFSET
                    IF workOrder != NULL
                        info:Result := workOrder:OrderBag:_LockOffSet
                    ELSE
                        info:Result := 0
                    ENDIF
                CASE DBOI_SETCODEBLOCK
                    IF workOrder != NULL
                        info:Result := workOrder:KeyCodeBlock
                    ENDIF
                CASE DBOI_KEYVAL
                    IF workOrder != NULL
                        isOk := TRUE
                        TRY
                            info:Result := SELF:EvalBlock(workOrder:KeyCodeBlock)
                        CATCH ex AS Exception
                            isOk := FALSE
                            SELF:_dbfError(ex, Subcodes.EDB_EXPRESSION, Gencode.EG_SYNTAX, "DBFCDX.OrderInfo")
                        END TRY
                        IF !isOk
                            info:Result := NULL
                        ENDIF
                    ELSE
                        info:Result := NULL
                    ENDIF
                CASE DBOI_SCOPETOPCLEAR
                CASE DBOI_SCOPEBOTTOMCLEAR
                    IF workOrder != NULL
                        workOrder:SetOrderScope(info:Result, (DbOrder_Info) nOrdinal)
                    ENDIF
                    info:Result := NULL
                CASE DBOI_SCOPETOP
                CASE DBOI_SCOPEBOTTOM
                    IF workOrder != NULL
                        LOCAL oldValue as OBJECT
                        IF nOrdinal == DBOI_SCOPETOP
                            oldValue := workOrder:TopScope
                        ELSEIF nOrdinal == DBOI_SCOPEBOTTOM
                            oldValue := workOrder:BottomScope
                        ELSE
                            oldValue := NULL
                        ENDIF
                        IF info:Result != NULL
                            workOrder:SetOrderScope(info:Result, (DbOrder_Info) nOrdinal)
                        ENDIF
                        info:Result := oldValue
                    ELSE
                        info:Result := NULL
                    ENDIF
                CASE DBOI_KEYADD
                    IF workOrder != NULL
                        info:Result := workOrder:AddKey(SELF:RecNo)
                    ELSE
                        info:Result := FALSE
                    ENDIF
                CASE DBOI_KEYDELETE
                    IF workOrder != NULL
                        info:Result := workOrder:DeleteKey(SELF:RecNo)
                    ELSE
                        info:Result := FALSE
                    ENDIF
                CASE DBOI_CUSTOM
                    IF workOrder != NULL
                        LOCAL lOld AS LOGIC
                        lOld := workOrder:Custom
                        IF info:Result IS LOGIC VAR custom
                            IF custom
                                workOrder:SetCustom()
                            ENDIF
                        ENDIF
                        info:Result := lOld
                    ELSE
                        info:Result := FALSE
                    ENDIF
                    
                CASE DBOI_USER + 42
                CASE DBOI_DUMP
                    // Dump Cdx to Txt file
                    IF workOrder != NULL
                        workOrder:_dump()
                    ENDIF
                    
                CASE DBOI_VALIDATE
                    // Validate integrity of the current Order
                    IF workOrder != NULL
                        info:Result := workOrder:_validate()
                    ENDIF
                OTHERWISE
                    SUPER:OrderInfo(nOrdinal, info)
                END SWITCH
                RETURN info:Result
                
            #endregion
        #region relations
        METHOD ForceRel() AS LOGIC
            LOCAL isOk    := TRUE AS LOGIC
            IF SELF:_RelInfoPending != NULL
                // Save the current context
                LOCAL currentRelation := SELF:_RelInfoPending AS DbRelInfo
                SELF:_RelInfoPending := NULL
                VAR oParent := (DBFCDX) currentRelation:Parent 
                IF oParent:EoF
                    //
                    isOk := SELF:GoTo( 0 )
                ELSE
                    isOk := SELF:RelEval( currentRelation )
                    
                    IF isOk .AND. !((DBFCDX)currentRelation:Parent):EoF
                        TRY
                            LOCAL seekInfo AS DbSeekInfo
                            seekInfo := DbSeekInfo{}
                            seekInfo:Value := SELF:_EvalResult
                            seekInfo:SoftSeek := FALSE
                            isOk := SELF:Seek(seekInfo)
                            
                        CATCH ex AS InvalidCastException
                            SELF:_dbfError(ex, Subcodes.ERDD_DATATYPE,Gencode.EG_DATATYPE,  "DBFNTX.ForceRel") 
                            
                        END TRY
                    ENDIF
                ENDIF
            ENDIF
            
            RETURN isOk
            #endregion
        #region Pack, Zap
        METHOD Pack() AS LOGIC
            LOCAL isOk AS LOGIC
            
            isOk := SUPER:Pack()
            IF isOk
                isOk := SELF:OrderListRebuild()
            ENDIF
            RETURN isOk
            
        PUBLIC METHOD Zap() AS LOGIC
            LOCAL isOk AS LOGIC
            
            isOk := SUPER:Zap()
            IF isOk
                isOk := SELF:OrderListRebuild()
            ENDIF
            RETURN isOk
            
        #endregion
        
        #region Open, Close, Create
        
        PUBLIC OVERRIDE METHOD Close() AS LOGIC
            LOCAL orderInfo AS DbOrderInfo
            BEGIN LOCK SELF
                SELF:GoCold()
                orderInfo := DbOrderInfo{}
                orderInfo:AllTags := TRUE
                SELF:_CloseAllIndexes(orderInfo, TRUE)
                RETURN SUPER:Close()
            END LOCK
        
        PUBLIC OVERRIDE METHOD Create( openInfo AS DbOpenInfo ) AS LOGIC
            LOCAL isOk AS LOGIC
            LOCAL lMemo := FALSE AS LOGIC
            isOk := SUPER:Create(openInfo)
            IF isOk
                FOREACH VAR fld IN SELF:_Fields
                    IF fld:FieldType:IsMemo()
                        lMemo := TRUE
                        EXIT
                    ENDIF
                NEXT
                LOCAL cIndex AS STRING
                // Delete index because it may have incorrect index expressions
                cIndex := System.IO.Path.ChangeExtension(SELF:FullPath, ".CDX")
                IF System.IO.File.Exists(cIndex)
                    System.IO.File.Delete(cIndex)
                ENDIF
                IF lMemo
                    SELF:_Header:Version := DBFVersion.FoxPro2WithMemo
                ELSE
                    SELF:_Header:Version := DBFVersion.FoxBaseDBase3NoMemo
                ENDIF
            ENDIF    
            RETURN isOk
            
        
        METHOD Open(info AS DbOpenInfo) AS LOGIC
            LOCAL lOk AS LOGIC
            lOk := SUPER:Open(info)
            IF lOk
                // Open structural index
                IF RuntimeState.AutoOpen
                    SELF:OpenProductionIndex(info)
                ENDIF
            ENDIF
            RETURN lOk
            
        PROTECTED METHOD OpenProductionIndex(info AS DbOpenInfo) AS VOID
            VAR cExt  := CdxOrderBag.GetIndexExtFromDbfExt(info:FileName)
            IF ! String.IsNullOrEmpty(cExt)
                VAR cCdxFileName := System.IO.Path.ChangeExtension(info:FileName, cExt)
                IF System.IO.File.Exists(cCdxFileName)
                    LOCAL orderinfo := DbOrderInfo{} AS DbOrderInfo
                    orderinfo:BagName := cCdxFileName
                    SELF:_indexList:Add(orderinfo, TRUE)
                    SELF:Header:HasTags |= DBFTableFlags.HasStructuralCDX
                ELSE
                    SELF:Header:HasTags &= _NOT(DBFTableFlags.HasStructuralCDX)
                ENDIF
            ENDIF
            
        #endregion
        
        
        
        #REGION Move
        
        INTERNAL METHOD ReadRecord() AS LOGIC
            RETURN SELF:_readRecord()
            
            
        PUBLIC METHOD Seek(seekInfo AS DbSeekInfo ) AS LOGIC
            LOCAL isOk AS LOGIC
            
            isOk := FALSE
            BEGIN LOCK SELF
                VAR index := SELF:CurrentOrder
                IF index != NULL
                    isOk := index:Seek(seekInfo)
                ENDIF
                IF  !isOk 
                    SELF:_dbfError(Subcodes.ERDD_DATATYPE, Gencode.EG_NOORDER )
                ENDIF
                SELF:_CheckEofBof()
            END LOCK
            RETURN isOk
            
        PUBLIC METHOD GoBottom() AS LOGIC
            BEGIN LOCK SELF
                LOCAL result AS LOGIC    
                IF SELF:CurrentOrder != NULL
                    result := SELF:CurrentOrder:GoBottom()
                    if (! result)
                        SELF:_SetEOF(TRUE)
                        SELF:_SetBOF(TRUE)
                    ELSE
                        SELF:_CheckEofBof()
                    ENDIF
                ELSE
                    result := SUPER:GoBottom()
                ENDIF
                RETURN result
            END LOCK
        
        PUBLIC METHOD GoTop() AS LOGIC
            BEGIN LOCK SELF
                LOCAL result AS LOGIC    
                IF SELF:CurrentOrder != NULL
                    result := SELF:CurrentOrder:GoTop()
                    if (! result)
                        SELF:_SetEOF(TRUE)
                        SELF:_SetBOF(TRUE)
                    ELSE
                        SELF:_CheckEofBof()
                    ENDIF
                ELSE
                    result := SUPER:GoTop()
                ENDIF
                RETURN result
            END LOCK
        
        METHOD __Goto(nRec AS LONG) AS LOGIC
            // Skip without reset of topstack
            RETURN SUPER:GoTo(nRec)
            
        METHOD GoTo(nRec AS LONG) AS LOGIC
            LOCAL result AS LOGIC    
            SELF:GoCold()
            IF SELF:CurrentOrder != NULL
                SELF:CurrentOrder:ClearStack() // force to reseek later
            ENDIF
            result := SUPER:GoTo(nRec)
            RETURN result
            
            
        PUBLIC METHOD SkipRaw( move AS LONG ) AS LOGIC
            BEGIN LOCK SELF
                LOCAL result AS LOGIC    
                IF SELF:CurrentOrder != NULL
                    result := SELF:CurrentOrder:SkipRaw(move)
                    SELF:_CheckEofBof()
                ELSE
                    result := SUPER:SkipRaw(move)
                ENDIF
                RETURN result
            END LOCK
            
        #ENDREGION
        
        #REGION GoCold, GoHot, Flush
        PUBLIC OVERRIDE METHOD GoCold() AS LOGIC
            LOCAL isOk AS LOGIC
            
            isOk := TRUE
            BEGIN LOCK SELF
                IF !SELF:IsHot 
                    RETURN isOk
                ENDIF
                isOk := SELF:_indexList:GoCold() 
                IF !isOk
                    RETURN isOk
                ENDIF
                RETURN SUPER:GoCold()
            END LOCK
        
        PUBLIC OVERRIDE METHOD GoHot() AS LOGIC
            LOCAL isOk AS LOGIC
            
            isOk := TRUE
            BEGIN LOCK SELF
                isOk := SUPER:GoHot()
                IF !isOk
                    RETURN isOk
                ENDIF
                RETURN SELF:_indexList:GoHot()
            END LOCK
        
        PUBLIC OVERRIDE METHOD Flush() AS LOGIC
            LOCAL isOk AS LOGIC
            
            isOk := TRUE
            BEGIN LOCK SELF
                isOk := SUPER:Flush()
                RETURN SELF:_indexList:Flush() .AND. isOk
            END LOCK
            
        #ENDREGION
    END CLASS    
    
END NAMESPACE
