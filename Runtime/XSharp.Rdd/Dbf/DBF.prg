//
// Copyright (c) XSharp B.V.  All Rights Reserved.
// Licensed under the Apache License, Version 2.0.
// See License.txt in the project root for license information.
//

// Please note that this code code expects zero based arrays

USING System.Runtime.InteropServices
USING System.IO
USING System.Text
USING System.Linq
USING XSharp.RDD.Enums
USING XSharp.RDD.Support
USING System.Globalization
USING System.Collections.Generic
USING System.Diagnostics

BEGIN NAMESPACE XSharp.RDD
    /// <summary>DBF RDD. Usually not used 'stand alone'</summary>
[DebuggerDisplay("DBF ({Alias,nq})")];
PARTIAL CLASS DBF INHERIT Workarea IMPLEMENTS IRddSortWriter
#region STATIC properties and fields
        STATIC PROTECT _Extension := ".DBF" AS STRING
        STATIC PRIVATE  culture := System.Globalization.CultureInfo.InvariantCulture AS CultureInfo
	
#endregion	
	PROTECT _RelInfoPending  AS DbRelInfo
	
	PROTECT _Header			AS DbfHeader
	PROTECT _HeaderLength	AS LONG  	// Size of header
	PROTECT _BufferValid	AS LOGIC	// Current Record is Valid
	PROTECT _BlankBuffer    AS BYTE[]
	INTERNAL _isValid        AS LOGIC    // Current Position is Valid
	PROTECT _HasMemo		AS LOGIC
	PROTECT _wasChanged     AS LOGIC
	
    //PROTECT _HasTags		AS LOGIC
    //PROTECT _HasAutoInc		AS LOGIC
    //PROTECT _HasTimeStamp	AS LOGIC
    //PROTECT _LastUpdate	    AS DateTime
	PROTECT _RecCount		AS LONG
	PROTECT _RecNo			AS LONG
    //PROTECT _Temporary		AS LOGIC
	PROTECT _RecordChanged	AS LOGIC 	// Current record has changed ?
	PROTECT _Positioned		AS LOGIC 	//
    //PROTECT _Appended		AS LOGIC	// Record has been added ?
    PROTECT _Deleted		AS LOGIC	// Record has been deleted ?
    //PROTECT _HeaderDirty	AS LOGIC	// Header is dirty ?
    PROTECT _fLocked		AS LOGIC    // File Locked ?
    PROTECT _HeaderLocked	AS LOGIC
    //PROTECT _PackMemo		AS LOGIC
    INTERNAL _OpenInfo		AS DbOpenInfo // current dbOpenInfo structure in OPEN/CREATE method
    PROTECT _Locks			AS List<LONG>
    PROTECT _AllowedFieldTypes AS STRING
    //PROTECT _DirtyRead		AS LONG
    //PROTECT _HasTrigger		AS LOGIC
    //PROTECT _Encrypted		AS LOGIC	// Current record Encrypted
    //PROTECT _TableEncrypted 	AS LOGIC	// Whole table encrypted
    //PROTECT _CryptKey		AS STRING
    //PROTRECT _Trigger		as DbTriggerDelegate
	PROTECT _oIndex			AS BaseIndex
	PROTECT _Hot            AS LOGIC
	PROTECT _lockScheme     AS DbfLocking
	PROTECT _NewRecord      AS LOGIC
    PROTECT INTERNAL _NullColumn    AS DbfNullColumn            // Column definition for _NullFlags, used in DBFVFP driver
    PROTECT INTERNAL _NullCount      := 0 AS LONG   // to count the NULL and Length bits for DBFVFP
	
    PROTECT INTERNAL PROPERTY FullPath AS STRING GET _FileName
    PROTECT INTERNAL PROPERTY Header AS DbfHeader GET _Header
    PROTECT INTERNAL _Ansi          AS LOGIC
    PROTECT INTERNAL _Encoding      AS Encoding
    PROTECT INTERNAL _numformat AS NumberFormatInfo
    PROTECT PROPERTY IsOpen AS LOGIC GET SELF:_hFile != F_ERROR
    PROTECT PROPERTY HasMemo AS LOGIC GET SELF:_HasMemo
    NEW PROTECT PROPERTY Memo AS BaseMemo GET (BaseMemo) SELF:_Memo


PROTECTED METHOD ConvertToMemory() AS LOGIC
     IF !SELF:_OpenInfo:Shared
        FConvertToMemoryStream(SELF:_hFile)
        IF SELF:_Memo IS DBTMemo VAR dbtmemo
            FConvertToMemoryStream(dbtmemo:_hFile)
        ELSEIF SELF:_Memo IS FPTMemo VAR fptmemo
            FConvertToMemoryStream(fptmemo:_hFile)
        ENDIF
        RETURN TRUE
     ENDIF
     RETURN FALSE

INTERNAL METHOD _CheckEofBof() AS VOID
    IF SELF:RecCount == 0
        SELF:_SetEOF(TRUE)
        SELF:_SetBOF(TRUE)
    ENDIF


INTERNAL METHOD _SetBOF(lNewValue as LOGIC) AS VOID
    IF lNewValue != SELF:BoF
        SELF:BoF := lNewValue
    ENDIF


INTERNAL METHOD _SetEOF(lNewValue as LOGIC) AS VOID
    IF lNewValue != SELF:EoF
        SELF:EoF := lNewValue
        IF lNewValue
            Array.Copy(SELF:_BlankBuffer, SELF:_RecordBuffer, SELF:_RecordLength)
        ENDIF
    ENDIF
    
PRIVATE METHOD _AllocateBuffers() AS VOID
	SELF:_RecordBuffer  := BYTE[]{ SELF:_RecordLength}
	SELF:_BlankBuffer   := BYTE[]{ SELF:_RecordLength}
	FOR VAR  i := 0 TO SELF:_RecordLength - 1 
		SELF:_BlankBuffer[i] := 0x20 // space
	NEXT
	FOREACH oFld AS RddFieldInfo IN _Fields
		IF oFld IS DbfColumn VAR column
			column:InitValue(SELF:_BlankBuffer)
		ENDIF
	NEXT
	
CONSTRUCTOR()
	SELF:_hFile := F_ERROR
	SELF:_Header := DbfHeader{} 
	SELF:_Header:initialize()
	SELF:_Locks     := List<LONG>{}
	SELF:_numformat := (NumberFormatInfo) culture:NumberFormat:Clone()
	SELF:_numformat:NumberDecimalSeparator := "."
	SELF:_RelInfoPending    := NULL
	SELF:_AllowedFieldTypes := "CDLMN"
	
            /// <inheritdoc />
METHOD GoTop() AS LOGIC
	IF SELF:IsOpen
		BEGIN LOCK SELF
			SELF:GoTo( 1 )
			SELF:_Top := TRUE
			SELF:_Bottom := FALSE
			SELF:_BufferValid := FALSE
                // Apply Filter and SetDeleted
			VAR result := SkipFilter(1)
            SELF:_CheckEofBof()
            RETURN result
        END LOCK
	ENDIF
RETURN FALSE

    /// <inheritdoc />
METHOD GoBottom() AS LOGIC
	IF SELF:IsOpen
		BEGIN LOCK SELF
			SELF:GoTo( SELF:RecCount )
			SELF:_Top := FALSE
			SELF:_Bottom := TRUE
			SELF:_BufferValid := FALSE
            // Apply Filter and SetDeleted
			VAR result := SkipFilter(-1)
            SELF:_CheckEofBof()
            RETURN result
        END LOCK
	ENDIF
RETURN FALSE

/// <inheritdoc />
METHOD GoTo(nRec AS LONG) AS LOGIC
	IF SELF:IsOpen
		BEGIN LOCK SELF
        // Validate any pending change
			SELF:GoCold()
            // On Shared env, it can be correct to guess that some changes have been made
			IF SELF:Shared .AND. nRec > SELF:_RecCount 
				SELF:_RecCount := SELF:_calculateRecCount()
			ENDIF
            LOCAL nCount := SELF:_RecCount AS LONG
			IF  nRec <= nCount  .AND.  nRec > 0 
                // Normal positioning
                // VO does not set _Found to TRUE for a succesfull Goto. It does set _Found to false for a failed Goto
                //? SELF:CurrentThreadId, "Set Recno to ", Nrec
				SELF:_RecNo := nRec
				SELF:_SetEOF(FALSE)
                SELF:_SetBOF(FALSE)
                //SELF:_Found :=TRUE    
				SELF:_BufferValid := FALSE
				SELF:_isValid := TRUE
			ELSEIF nRec < 0 .AND. nCount > 0
                // skip to BOF. Move to record 1. 
				SELF:_RecNo := 1
                //? SELF:CurrentThreadId, "Set Recno to ", 1, "nRec", nRec, "nCount", nCount
				SELF:_SetEOF(FALSE)
                SELF:_SetBOF(TRUE)
				SELF:_Found :=FALSE
				SELF:_BufferValid := FALSE
				SELF:_isValid := FALSE
			ELSE
                // File empty, or move after last record
                //? SELF:CurrentThreadId, "Set Recno to nCount+1", nCount+1
				SELF:_RecNo := nCount + 1
				SELF:_SetEOF(TRUE)
                SELF:_SetBOF(nCount == 0)
				SELF:_Found := FALSE
				SELF:_BufferValid := FALSE
				SELF:_isValid := FALSE
            ENDIF
            IF SELF:_Relations:Count != 0
                SELF:SyncChildren()
            ENDIF
            SELF:_CheckEofBof()
			RETURN TRUE
		END LOCK
    ENDIF
RETURN FALSE

/// <inheritdoc />
METHOD GoToId(oRec AS OBJECT) AS LOGIC
	LOCAL result AS LOGIC
	BEGIN LOCK SELF
		TRY
			VAR nRec := Convert.ToInt32( oRec )
			result := SELF:GoTo( nRec )
		CATCH ex AS Exception
			SELF:_dbfError(ex, Subcodes.EDB_GOTO,Gencode.EG_DATATYPE,  "DBF.GoToId") 
			result := FALSE
		END TRY
    END LOCK
    SELF:_CheckEofBof()
RETURN result

/// <inheritdoc />
METHOD SetFilter(info AS DbFilterInfo) AS LOGIC
	SELF:ForceRel()
RETURN SUPER:SetFilter(info)			

    /// <inheritdoc />
METHOD Skip(nToSkip AS INT) AS LOGIC
	LOCAL result := FALSE AS LOGIC
	SELF:ForceRel()
	IF SELF:IsOpen
		SELF:_Top := FALSE
		SELF:_Bottom := FALSE
		LOCAL delState := XSharp.RuntimeState.Deleted AS LOGIC
        // 
		IF nToSkip == 0  .OR. delState .OR. ( SELF:_FilterInfo != NULL .AND. SELF:_FilterInfo:Active )
            // 
			result := SUPER:Skip( nToSkip )
		ELSE
			result := SELF:SkipRaw( nToSkip )
            // We reached the top ?
			IF result
                IF ( nToSkip < 0 ) .AND. SELF:_BoF
				    SELF:GoTop()
				    SELF:BoF := TRUE
			    ENDIF
			    IF nToSkip < 0 
				    SELF:_SetEOF(FALSE)
			    ELSEIF nToSkip > 0 
				    SELF:BoF := FALSE
                ENDIF
             ENDIF
        ENDIF
	ENDIF
    SELF:_CheckEofBof()
RETURN result


    /// <inheritdoc />
METHOD SkipRaw(nToSkip AS INT) AS LOGIC 
	LOCAL isOK := TRUE AS LOGIC
    LOCAL nNewRec as INT
    //
	IF nToSkip == 0 
        // Refresh current Recno
		LOCAL currentBof := SELF:BoF AS LOGIC
		LOCAL currentEof := SELF:EoF AS LOGIC
		SELF:GoTo( SELF:_RecNo )
		SELF:_SetBOF(currentBof)
        SELF:_SetEOF(currentEof)
	ELSE
        nNewRec := SELF:_RecNo + nToSkip
        IF nNewRec != 0
		    isOK := SELF:GoTo( SELF:_RecNo + nToSkip )
        ELSE
            isOK := SELF:GoTo( 1 )
            SELF:_SetBOF(TRUE)
        ENDIF
    ENDIF
    SELF:_CheckEofBof()
RETURN isOK 


    // Append and Delete
/// <inheritdoc />
METHOD Append(lReleaseLock AS LOGIC) AS LOGIC
	LOCAL isOK := FALSE AS LOGIC
	IF SELF:IsOpen
		BEGIN LOCK SELF
        // Validate
			isOK := SELF:GoCold()
			IF isOK 
            //
				IF SELF:_ReadOnly 
                // Error !! Cannot be written !
					SELF:_dbfError( ERDD.READONLY, XSharp.Gencode.EG_READONLY )
					isOK := FALSE
				ENDIF
				IF  SELF:Shared 
					IF  SELF:_Locks:Count > 0  .AND. lReleaseLock
						SELF:UnLock( 0 ) // Unlock All Records
					ENDIF
					isOK := SELF:AppendLock( DbLockMode.Lock )  // Locks Header and then future new record. Sets _HeaderLocked to TRUE
                ELSE
					SELF:_HeaderLocked := FALSE
				ENDIF
				IF isOK 
                    VAR nCount := SELF:_calculateRecCount()+1
					SELF:_UpdateRecCount(nCount)      // writes the reccount to the header as well
					SELF:_RecNo         := nCount
					Array.Copy(SELF:_BlankBuffer, SELF:_RecordBuffer, SELF:_RecordLength)
					FOREACH oFld AS RddFieldInfo IN _Fields
						IF oFld IS DbfColumn VAR column
							column:NewRecord(SELF:_RecordBuffer)
						ENDIF   
					NEXT
                    SELF:_writeRecord()
                    SELF:_putEndOfFileMarker()
                    // Now, update state
					SELF:_SetEOF(FALSE)
					SELF:BoF            := FALSE
					SELF:_Deleted       := FALSE
					SELF:_BufferValid   := TRUE
					SELF:_isValid       := TRUE
					SELF:_NewRecord     := TRUE
                    SELF:_wasChanged    := TRUE 
                    // Mark RecordBuffer as Hot
					SELF:_Hot           := TRUE
                    // Now, Save
					IF SELF:_HeaderLocked 
						SELF:GoCold()
						isOK := SELF:AppendLock( DbLockMode.UnLock ) // unlocks just header 
					ENDIF
				ENDIF
			ENDIF
		END LOCK
	ENDIF
//
RETURN isOK

PRIVATE METHOD _UpdateRecCount(nCount AS LONG) as LOGIC
	SELF:_RecCount          := nCount
	SELF:_Header:isHot      := TRUE
    SELF:_Header:RecCount   := nCount
    SELF:_wasChanged        := TRUE
    SELF:_writeHeader()
RETURN TRUE


/// <inheritdoc />
METHOD AppendLock( lockMode AS DbLockMode ) AS LOGIC
	LOCAL isOK := FALSE AS LOGIC
	BEGIN LOCK SELF
		IF lockMode == DbLockMode.Lock
            // Lock the "future" record (Recno+1) and the Header
			isOK := SELF:HeaderLock( lockMode )
			IF isOK 
                VAR newRecno := SELF:_calculateRecCount() +1
				IF !SELF:_Locks:Contains( newRecno ) .AND. !SELF:_fLocked
					isOK := SELF:_lockRecord( newRecno )
				ENDIF
				IF !isOK
                    // when we fail to lock the record then also unlock the header
					IF SELF:_HeaderLocked
                        //? CurrentThreadId," Failed to lock the new record", newRecno, "Unlock the header"
						SELF:HeaderLock( DbLockMode.UnLock )
                    ELSE
                        NOP
                        //? CurrentThreadId," Failed to lock the new record", newRecno, "but header was not locked ?"
					ENDIF
					SELF:_dbfError( ERDD.APPENDLOCK, XSharp.Gencode.EG_APPENDLOCK )
                ELSE
                    SELF:_RecNo := newRecno
                    //? CurrentThreadId, "Appended and Locked record ", newRecno, "Recno = ", SELF:RecNo
                ENDIF
            ELSE
                NOP
                //? CurrentThreadId,"AppendLock failed, header can't be locked"
			ENDIF
		ELSE
            // Unlock the Header, new record remains locked
			isOK := SELF:HeaderLock( lockMode )
		ENDIF
	END LOCK
    //
RETURN isOK

    // LockMethod.File      : Unlock all records and Lock the File
    // LockMethod.Exclusive : Unlock all records and lock the indicated record
    // LockMethod.Multiple  : Loc the indicated record
    /// <inheritdoc />
METHOD Lock( lockInfo REF DbLockInfo ) AS LOGIC
	LOCAL isOK AS LOGIC
	SELF:ForceRel()
	BEGIN LOCK SELF
		IF lockInfo:@@Method == DbLockInfo.LockMethod.Exclusive  .OR. ;
            lockInfo:@@Method == DbLockInfo.LockMethod.Multiple 
			isOK := SELF:_lockRecord( lockInfo )
		ELSEIF lockInfo:@@Method == DbLockInfo.LockMethod.File 
			isOK := SELF:_lockDBFFile( )
		ELSE
			isOK := TRUE
		ENDIF
	END LOCK
RETURN isOK

    // Place a lock on the Header. The "real" offset locked depends on the Lock Scheme, defined by the DBF Type
    /// <inheritdoc />
METHOD HeaderLock( lockMode AS DbLockMode ) AS LOGIC
    //
	IF lockMode == DbLockMode.Lock 
        //? CurrentThreadId, "Start Header Lock", ProcName(1)
        LOCAL nTries := 0 AS LONG
        DO WHILE TRUE
            ++nTries
		    SELF:_HeaderLocked := SELF:_tryLock( SELF:_lockScheme:Offset, 1,FALSE)
            IF ! SELF:_HeaderLocked
                System.Threading.Thread.Sleep(100)
                
            ELSE
                EXIT
            ENDIF
        ENDDO
        //? CurrentThreadId, "Header Lock", SELF:_HeaderLocked , "tries", nTries
        RETURN SELF:_HeaderLocked 
    ELSE
        
		TRY
            //? CurrentThreadId, "Start Header UnLock",ProcName(1)
			VAR unlocked := FFUnLock64( SELF:_hFile, SELF:_lockScheme:Offset, 1 )
			IF unlocked
				SELF:_HeaderLocked := FALSE
            ENDIF
            //? CurrentThreadId, "Header UnLock", unlocked
		CATCH ex AS Exception
			SELF:_HeaderLocked := FALSE
			SELF:_dbfError(ex, Subcodes.ERDD_WRITE_UNLOCK,Gencode.EG_LOCK_ERROR,  "DBF.HeaderLock") 
        END TRY
        RETURN TRUE 
	ENDIF
    //


    // Unlock a indicated record number. If 0, Unlock ALL records
    // Then unlock the File if needed
/// <inheritdoc />
METHOD UnLock(oRecId AS OBJECT) AS LOGIC
	LOCAL recordNbr AS LONG
	LOCAL isOK AS LOGIC
    //
	IF SELF:Shared 
		BEGIN LOCK SELF
    //
            //? CurrentThreadId, "UnLock", oRecId
			SELF:GoCold()
			TRY
				recordNbr := Convert.ToInt32( oRecId )
			CATCH ex AS Exception
				recordNbr := 0
				SELF:_dbfError(ex, Subcodes.ERDD_DATATYPE,Gencode.EG_LOCK_ERROR,  "DBF.UnLock") 
			END TRY
        //
			isOK := TRUE
            IF recordNbr != 0
                NOP
            ENDIF
			IF SELF:_Locks:Count > 0
				IF recordNbr == 0 
                // Create a copy with ToArray() because _unlockRecord modifies the collection
					FOREACH VAR nbr IN SELF:_Locks:ToArray()
						isOK := isOK .AND. SELF:_unlockRecord( nbr )
					NEXT
					SELF:_Locks:Clear()  // Should be useless as the record is removed from the list in _unlockRecord
				ELSE
					isOK := SELF:_unlockRecord( recordNbr )
				ENDIF
			ENDIF
			IF SELF:_fLocked  .AND. recordNbr == 0 
				isOK := SELF:_unlockFile( )
				IF isOK
					SELF:_fLocked := FALSE
				ENDIF
            ENDIF
		END LOCK
    ELSE
        //? CurrentThreadId, "UnLock nothing to do because not shared"
		isOK := TRUE
	ENDIF
RETURN isOK

    // Unlock file. The Offset depends on the LockScheme
PROTECT METHOD _unlockFile( ) AS LOGIC
	LOCAL unlocked AS LOGIC
    //
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	
	TRY
		unlocked := FFUnLock64( SELF:_hFile, SELF:_lockScheme:FileLockOffSet, SELF:_lockScheme:FileSize )
	CATCH ex AS Exception
		unlocked := FALSE
		SELF:_dbfError(ex, Subcodes.ERDD_WRITE_UNLOCK,Gencode.EG_LOCK_ERROR,  "DBF._unlockFile") 
	END TRY
RETURN unlocked

PROTECTED PROPERTY CurrentThreadId AS STRING GET System.Threading.Thread.CurrentThread:ManagedThreadId:ToString()

    // Unlock a record. The Offset depends on the LockScheme
PROTECT METHOD _unlockRecord( recordNbr AS LONG ) AS LOGIC
	LOCAL unlocked AS LOGIC
	LOCAL iOffset AS INT64
	IF ! SELF:IsOpen
		RETURN FALSE
    ENDIF
    
	TRY
    	iOffset := SELF:_lockScheme:RecnoOffSet(recordNbr, SELF:_RecordLength , SELF:_HeaderLength )
		unlocked := FFUnLock64( SELF:_hFile, iOffset, SELF:_lockScheme:RecordSize )
        //? CurrentThreadId, "unlocked record ", recordNbr
	CATCH ex AS Exception
		unlocked := FALSE
        //? CurrentThreadId, "failed to unlock record ", recordNbr
		SELF:_dbfError(ex, Subcodes.ERDD_WRITE_UNLOCK,Gencode.EG_LOCK_ERROR,  "DBF._unlockRecord") 
	END TRY
	IF( unlocked )
		SELF:_Locks:Remove( recordNbr )
	ENDIF
RETURN unlocked

    // Lock the file. The Offset depends on the LockScheme
PROTECT METHOD _lockFile( ) AS LOGIC
	LOCAL locked AS LOGIC
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	
	TRY
		locked := FFLock64( SELF:_hFile, SELF:_lockScheme:FileLockOffSet, SELF:_lockScheme:FileSize )
	CATCH ex AS Exception
		locked := FALSE
		SELF:_dbfError(ex, Subcodes.ERDD_WRITE_LOCK,Gencode.EG_LOCK_ERROR,  "DBF._lockFile") 
	END TRY
RETURN locked

    // Place a lock : <nOffset> indicate where the lock should be; <nLong> indicate the number bytes to lock
    // If it fails, the operation is tried <nTries> times, waiting 1ms between each operation.
    // Return the result of the operation
PROTECTED METHOD _tryLock( nOffset AS INT64, nLong AS INT64, lGenError AS LOGIC) AS LOGIC
	LOCAL locked AS LOGIC
    LOCAL nTries AS LONG
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	LOCAL lockEx := NULL AS Exception
    nTries := 123
	REPEAT
		TRY
			locked := FFLock64( SELF:_hFile, nOffset, nLong )
        CATCH ex AS Exception
            lockEx := ex
			locked := FALSE
		END TRY
		IF !locked
            LOCAL nError := FError() AS DWORD
            IF nError != 33     // Someone else has locked the file
                EXIT
            ENDIF
			nTries --
            //DebOut32(ProcName(1)+" Lock Failed "+nTries:ToString()+" tries left, offset: "+ nOffSet:ToString()+" length: "+nLong:ToString())
			IF nTries > 0 
				System.Threading.Thread.Sleep( 10)
            ENDIF
		ENDIF
	UNTIL ( locked .OR. (nTries==0) )
    IF (! locked .AND. lGenError)
		 SELF:_dbfError(lockEx, Subcodes.ERDD_WRITE_LOCK,Gencode.EG_LOCK_ERROR,  "DBF._tryLock") 
    ENDIF

RETURN locked

    // Lock the DBF File : All records are first unlocked, then the File is locked
PROTECTED METHOD _lockDBFFile() AS LOGIC
	LOCAL isOK := TRUE AS LOGIC
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	
	IF SELF:Shared .AND. !SELF:_fLocked 
        //
		SELF:GoCold()
		IF SELF:_Locks:Count > 0 
            // create a copy of the collection by calling ToArray to avoid a runtime error
            // because the collection will be changed by the call to _unlockRecord()
			FOREACH VAR nbr IN SELF:_Locks:ToArray()
				SELF:_unlockRecord( nbr )
			NEXT
			SELF:_Locks:Clear()
		ENDIF
		SELF:_fLocked := SELF:_lockFile()
        // Invalidate Buffer
		SELF:GoTo( SELF:RecNo )
		isOK := SELF:_fLocked
	ENDIF
RETURN isOK

    // Lock a record number. The Offset depends on the LockScheme
PROTECTED METHOD _lockRecord( recordNbr AS LONG ) AS LOGIC
	LOCAL locked AS LOGIC
	LOCAL iOffset AS INT64
    //
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	
    iOffset := SELF:_lockScheme:RecnoOffSet(recordNbr, SELF:_RecordLength , SELF:_HeaderLength )
    locked := SELF:_tryLock(iOffset, SELF:_lockScheme:RecordSize ,FALSE)
	IF locked
		SELF:_Locks:Add( recordNbr )
        //? CurrentThreadId, "Locked record ", recordNbr
    ELSE
        //? CurrentThreadId, "Failed to Lock record ", recordNbr
		SELF:_dbfError( Subcodes.ERDD_WRITE_LOCK,Gencode.EG_LOCK_ERROR,  "DBF._lockRecord") 
	ENDIF
RETURN locked


    // LockMethod.Exclusive : Unlock all records and lock the indicated record
    // LockMethod.Multiple  : Loc the indicated record
PROTECTED METHOD _lockRecord( lockInfo REF DbLockInfo ) AS LOGIC
	LOCAL nToLock := 0 AS UINT64
	LOCAL isOK AS LOGIC
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	
	isOK := TRUE
	IF lockInfo:RecId == NULL 
		nToLock := (UINT64)SELF:RecNo
	ELSE
		TRY
			nToLock := Convert.ToUInt64( lockInfo:RecId )
		CATCH ex AS Exception
			SELF:_dbfError( ex, ERDD.DATATYPE, XSharp.Gencode.EG_DATATYPE )
			isOK := FALSE
		END TRY
		IF isOK
			IF nToLock > SELF:RecCount  .OR. nToLock < 1 
				isOK := FALSE
			ENDIF
		ENDIF
	ENDIF
    //
	IF isOK 
        // Already locked ?
		IF SELF:Shared .AND. !SELF:_Locks:Contains( (LONG)nToLock ) 
            IF lockInfo:Method == DbLockInfo.LockMethod.Multiple 
                // Just add the lock to the list
				isOK := SELF:_lockRecord( (LONG)nToLock )
			ELSE // DbLockInfo.LockMethod.Exclusive
                // Release the locks
				SELF:UnLock(0)  
                // Now, lock the one
				isOK := SELF:_lockRecord( (LONG)nToLock )
                // Go to there
				SELF:GoTo( (LONG)nToLock )
			ENDIF
		ENDIF
	ENDIF
    //
	lockInfo:Result := isOK
RETURN isOK


    // Un Delete the curretn Record
/// <inheritdoc />
METHOD Recall() AS LOGIC
	LOCAL isOK AS LOGIC
	SELF:ForceRel()
	isOK := SELF:_readRecord()
	IF isOK
		IF ! SELF:_Hot
			SELF:GoHot()
		ENDIF
		SELF:_RecordBuffer[ 0 ] := (BYTE)' '
		SELF:_Deleted := FALSE
	ELSE
		SELF:_dbfError( ERDD.READ, XSharp.Gencode.EG_READ )
	ENDIF
RETURN isOK

    // Mark the current record as DELETED
/// <inheritdoc />
METHOD Delete() AS LOGIC
	LOCAL isOK AS LOGIC
	SELF:ForceRel()
	BEGIN LOCK SELF
		isOK := SELF:_readRecord()
		IF isOK
			IF SELF:_isValid
				IF ! SELF:_Hot
					SELF:GoHot()
				ENDIF
				SELF:_RecordBuffer[ 0 ] := (BYTE)'*'
				SELF:_Deleted := TRUE
            //
			ENDIF
		ELSE
        // VO does not report an error when deleting on an invalid record
			isOK := TRUE // SELF_DbfError( ERDD.READ, XSharp.Gencode.EG_READ )
		ENDIF
	END LOCK
RETURN isOK

    // Retrieve the raw content of a record
/// <inheritdoc />
METHOD GetRec() AS BYTE[]
	LOCAL records := NULL AS BYTE[]
	SELF:ForceRel()
    // Read Record to Buffer
	BEGIN LOCK SELF
		IF SELF:_readRecord()
        //
			records := BYTE[]{ SELF:_RecordLength }
			Array.Copy(SELF:_RecordBuffer, records, SELF:_RecordLength)
		ENDIF
	END LOCK
RETURN records

    // Put the content of a record as raw data
/// <inheritdoc />
METHOD PutRec(aRec AS BYTE[]) AS LOGIC
	LOCAL isOK := FALSE AS LOGIC
    // First, Check the Size
	IF aRec:Length == SELF:_RecordLength 
		IF SELF:_readRecord()
			IF ! SELF:_Hot
				isOK := SELF:GoHot()
			ELSE
				isOK := TRUE
			ENDIF
			Array.Copy(aRec, SELF:_RecordBuffer, SELF:_RecordLength)
		ENDIF
	ELSE
		SELF:_dbfError( ERDD.DATAWIDTH, XSharp.Gencode.EG_DATAWIDTH )
	ENDIF
RETURN isOK

    // Suppress all DELETED record
/// <inheritdoc />
METHOD Pack() AS LOGIC
	LOCAL isOK AS LOGIC
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	
	IF SELF:_ReadOnly 
        // Error !! Cannot be written !
		SELF:_dbfError( ERDD.READONLY, XSharp.Gencode.EG_READONLY )
		RETURN FALSE
	ENDIF
    //
	IF SELF:Shared 
        // Error !! Cannot be written !
		SELF:_dbfError( ERDD.SHARED, XSharp.Gencode.EG_SHARED )
		RETURN FALSE
	ENDIF
    //
	isOK := SELF:GoCold()
	IF isOK
		LOCAL nToRead AS LONG
		LOCAL nMoveTo AS LONG
		LOCAL nTotal AS LONG
		LOCAL lDeleted AS LOGIC
        //
		nToRead := 1
		nMoveTo := 1
		nTotal := 0
		WHILE nToRead <= SELF:RecCount 
            // Move
			SELF:GoTo( nToRead )
            // and get Data
			SELF:_readRecord()
			lDeleted := SELF:_Deleted
            //
			IF !lDeleted 
				nTotal++
				IF nToRead != nMoveTo 
					SELF:_RecNo := nMoveTo
					SELF:_writeRecord()
				ENDIF
			ENDIF
            // Next
			nToRead ++
			IF !lDeleted 
				nMoveTo++
			ENDIF
		ENDDO
        //
		SELF:_Hot := FALSE
		SELF:_UpdateRecCount(nTotal) // writes the reccount to the header as well
		SELF:Flush()
        SELF:_CheckEofBof()
        //
	ENDIF
RETURN isOK


    // Remove all records
/// <inheritdoc />
METHOD Zap() AS LOGIC
	LOCAL isOK AS LOGIC
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	
	IF SELF:_ReadOnly 
		SELF:_dbfError( ERDD.READONLY, XSharp.Gencode.EG_READONLY )
		RETURN FALSE
	ENDIF
	IF SELF:_Shared 
		SELF:_dbfError( ERDD.SHARED, XSharp.Gencode.EG_SHARED )
		RETURN FALSE
	ENDIF
    //
	isOK := SELF:GoCold()
	IF isOK
		SELF:GoTo(0)
        // Zap means, set the RecCount to zero, so any other write with overwrite datas
		SELF:_UpdateRecCount(0) // writes the reccount to the header as well
		SELF:Flush()
        // Memo File ?
		IF SELF:_HasMemo 
            // Zap Memo
			IF SELF:HasMemo
				RETURN _Memo:Zap()
			ELSE
				RETURN SUPER:Zap()
			ENDIF
		ENDIF
        SELF:_CheckEofBof()
    ENDIF
RETURN isOK

    // Open and Close
    /// <inheritdoc />
METHOD Close() 			AS LOGIC
	LOCAL isOK := FALSE AS LOGIC
	IF SELF:IsOpen
    // Validate
		isOK := SELF:GoCold()
    //
		IF isOK 
			SELF:UnLock(0)
			IF !SELF:_ReadOnly 
				SELF:Flush()
			ENDIF
			IF SELF:_HeaderLocked 
				SELF:HeaderLock( DbLockMode.UnLock )
			ENDIF
        ENDIF
		TRY
			isOK := FClose( SELF:_hFile )
			IF SELF:_HasMemo 
				SELF:CloseMemFile()
			ENDIF
				
			isOK := SUPER:Close() .AND. isOK
		CATCH ex AS Exception
			isOK := FALSE
			SELF:_dbfError(ex, Subcodes.ERDD_CLOSE_FILE,Gencode.EG_CLOSE,  "DBF.Close") 
				
		END TRY
		SELF:_hFile := F_ERROR
	ENDIF
RETURN isOK

    // Move to the End of file, and place a End-Of-File Marker (0x1A)
PRIVATE METHOD _putEndOfFileMarker() AS LOGIC
    // According to DBASE.com Knowledge base :
    // The end of the file is marked by a single byte, with the end-of-file marker, an OEM code page character value of 26 (0x1A).
	LOCAL lOffset   := SELF:_HeaderLength + SELF:_RecCount * SELF:_RecordLength AS LONG
	LOCAL eofMarker := <BYTE>{ 26 } AS BYTE[]
	LOCAL isOK      AS LOGIC
    // Note FoxPro does not write EOF character for files with 0 records
	isOK := ( FSeek3( SELF:_hFile, lOffset, FS_SET ) == lOffset ) 
	IF isOK 
		isOK := ( FWrite3( SELF:_hFile, eofMarker, 1 ) == 1 )
		IF isOK
            // Fix length of File
			isOK := FChSize( SELF:_hFile, (DWORD)lOffset+1)
		ENDIF
	ENDIF
RETURN isOK

    // Create a DBF File, based on the DbOpenInfo Structure
    // Write the File Header, and the Fields Header; Create the Memo File if needed
METHOD Create(info AS DbOpenInfo) AS LOGIC
	LOCAL isOK AS LOGIC
    //
	isOK := FALSE
	IF SELF:_Fields:Length == 0 
		RETURN FALSE
	ENDIF
	SELF:_OpenInfo := info
    // Should we set to .DBF per default ?
	IF String.IsNullOrEmpty(SELF:_OpenInfo:Extension)
		SELF:_OpenInfo:Extension := _Extension
        //
	ENDIF
	SELF:_OpenInfo:FileName := System.IO.Path.ChangeExtension( SELF:_OpenInfo:FileName, SELF:_OpenInfo:Extension )
    //
	SELF:_Hot := FALSE
	SELF:_FileName := SELF:_OpenInfo:FileName
	SELF:_Alias := SELF:_OpenInfo:Alias
	SELF:_Shared := SELF:_OpenInfo:Shared
	SELF:_ReadOnly := SELF:_OpenInfo:ReadOnly
    //
	SELF:_hFile    := FCreate2( SELF:_FileName, FO_EXCLUSIVE)
	IF SELF:IsOpen
		LOCAL fieldCount :=  SELF:_Fields:Length AS INT
		LOCAL fieldDefSize := fieldCount * DbfField.SIZE AS INT
		LOCAL codePage AS LONG
        IF XSharp.RuntimeState.Ansi
			SELF:_Ansi := TRUE
			codePage := XSharp.RuntimeState.WinCodePage
		ELSE
			SELF:_Ansi := FALSE
			codePage := XSharp.RuntimeState.DosCodePage
		ENDIF        // First, just the Header
		SELF:_Encoding := System.Text.Encoding.GetEncoding( codePage ) 

		SELF:_Header:HeaderLen := SHORT(DbfHeader.SIZE + fieldDefSize+ 2 ) 
		SELF:_Header:isHot := TRUE
        //


		IF SELF:_Ansi
			SELF:_lockScheme:Initialize( DbfLockingModel.VoAnsi )
		ELSE
			SELF:_lockScheme:Initialize( DbfLockingModel.Clipper52 )
		ENDIF
		
        //
        // Convert the Windows CodePage to a DBF CodePage
		SELF:_Header:CodePage := CodePageExtensions.ToHeaderCodePage( (OsCodepage)codePage ) 
        // Init Header version, should it be a parameter ?
        LOCAL lSupportAnsi := FALSE AS LOGIC
        SWITCH RuntimeState.Dialect
            CASE XSharpDialect.VO
            CASE XSharpDialect.Vulcan
            CASE XSharpDialect.Core
                lSupportAnsi := TRUE
            OTHERWISE
                lSupportAnsi := FALSE
        END SWITCH
         
		IF SELF:_Ansi .and. lSupportAnsi
			SELF:_Header:Version := IIF(SELF:_HasMemo, DBFVersion.VOWithMemo , DBFVersion.VO )
		ELSE
			SELF:_Header:Version := IIF(SELF:_HasMemo, DBFVersion.FoxBaseDBase3WithMemo , DBFVersion.FoxBaseDBase3NoMemo )
		ENDIF
        // This had been initialized by AddFields()
		SELF:_Header:RecordLen := (WORD) SELF:_RecordLength
        // This will fill the Date and RecCount
		isOK := SELF:_writeHeader()
        SELF:_wasChanged := TRUE
		IF isOK 
			SELF:_HeaderLength := SELF:_Header:HeaderLen
			isOK := SELF:_writeFieldsHeader()
			IF isOK 
				SELF:_RecordLength := SELF:_Header:RecordLen 
				IF SELF:_HasMemo 
					isOK := SELF:CreateMemFile( info )
				ENDIF
				SELF:_AllocateBuffers()
			ENDIF
		ENDIF
		IF !isOK 
			IF SELF:_HasMemo 
				SELF:CloseMemFile( )
			ENDIF
			FClose( SELF:_hFile )
		ELSE
			SELF:GoTop()
		ENDIF
	ELSE
		VAR ex := FException()
		SELF:_dbfError( ex, ERDD.CREATE_FILE, XSharp.Gencode.EG_CREATE )
	ENDIF
RETURN isOK



// Allow subclass (VFP) to set Extra flags
PROTECTED VIRTUAL METHOD _checkField( dbffld REF DbfField) AS LOGIC
    RETURN dbffld:Type:IsStandard()


    // Write the Fields Header, based on the _Fields List
PROTECTED VIRTUAL METHOD _writeFieldsHeader() AS LOGIC
	LOCAL isOK AS LOGIC
	LOCAL fieldCount :=  SELF:_Fields:Length AS INT
	LOCAL fieldDefSize := fieldCount * DbfField.SIZE AS INT
    // Now, create the Structure
	LOCAL fieldsBuffer := BYTE[]{ fieldDefSize +1 } AS BYTE[] // +1 to add 0Dh stored as the field terminator.
	LOCAL currentField := DbfField{} AS DbfField
    currentField:Encoding := SELF:_Encoding
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	
	currentField:initialize()
	LOCAL nOffSet AS LONG
	nOffSet := 0
	FOREACH VAR fld IN SELF:_Fields
		currentField:Offset := fld:Offset
		currentField:Name   := fld:Name
		currentField:Type   := fld:FieldType
		IF fld:FieldType != DbFieldType.Character
			currentField:Len := (BYTE) fld:Length
			currentField:Dec := (BYTE) fld:Decimals
		ELSE
			currentField:Len := (BYTE) (fld:Length % 256)
			IF fld:Length > Byte.MaxValue
				currentField:Dec := (BYTE) (fld:Length / 256)
			ELSE
				currentField:Dec := 0
			ENDIF
		ENDIF
		currentField:Flags := fld:Flags
		IF ! _checkField(REF currentField)
			SELF:_dbfError( ERDD.CREATE_FILE, XSharp.Gencode.EG_DATATYPE,"DBF:Create()", "Invalid "+fld:ToString())
			RETURN FALSE
		ENDIF
		Array.Copy(currentField:Buffer, 0, fieldsBuffer, nOffSet, DbfField.SIZE )
		nOffSet += DbfField.SIZE
	NEXT
	
	
    // Terminator
	fieldsBuffer[fieldDefSize] := 13
    // Go end of Header
	isOK := ( FSeek3( SELF:_hFile, DbfHeader.SIZE, SeekOrigin.Begin ) == DbfHeader.SIZE )
	IF isOK 
    // Write Fields and Terminator
		TRY
			isOK := ( FWrite3( SELF:_hFile, fieldsBuffer, (DWORD)fieldsBuffer:Length ) == (DWORD)fieldsBuffer:Length )
		CATCH ex AS Exception
			SELF:_dbfError( ex, ERDD.WRITE, XSharp.Gencode.EG_WRITE )
		END TRY
	ENDIF
    //
RETURN isOK

    /// <inheritdoc />
METHOD Open(info AS XSharp.RDD.Support.DbOpenInfo) AS LOGIC
	LOCAL isOK AS LOGIC
    //
	isOK := FALSE
	SELF:_OpenInfo := info
    // Should we set to .DBF per default ?
	IF String.IsNullOrEmpty(SELF:_OpenInfo:Extension)
		SELF:_OpenInfo:Extension := _Extension
	ENDIF
	SELF:_OpenInfo:FileName := System.IO.Path.ChangeExtension( SELF:_OpenInfo:FileName, SELF:_OpenInfo:Extension )
    //
	SELF:_Hot := FALSE
	SELF:_FileName := SELF:_OpenInfo:FileName
	IF File(SELF:_FileName)
		SELF:_FileName := FPathName()
		SELF:_OpenInfo:FileName := SELF:_FileName
	ENDIF
	SELF:_Alias := SELF:_OpenInfo:Alias
	SELF:_Shared := SELF:_OpenInfo:Shared
	SELF:_ReadOnly := SELF:_OpenInfo:ReadOnly
	SELF:_hFile    := FOpen(SELF:_FileName, SELF:_OpenInfo:FileMode)

	IF SELF:IsOpen
//        IF !SELF:_OpenInfo:Shared
//            FConvertToMemoryStream(SELF:_hFile)
//        ENDIF
		isOK := SELF:_readHeader()
		IF isOK 
			IF SELF:_HasMemo 
				isOK := SELF:OpenMemFile( info )
			ENDIF
			SELF:GoTop()
            //
			SELF:_Ansi := SELF:_Header:IsAnsi
			SELF:_Encoding := System.Text.Encoding.GetEncoding( CodePageExtensions.ToCodePage( SELF:_Header:CodePage )  )
            //
		ELSE
			SELF:_dbfError( ERDD.CORRUPT_HEADER, XSharp.Gencode.EG_CORRUPTION )
		ENDIF
	ELSE
        // Error or just FALSE ?
		isOK := FALSE
		LOCAL ex := FException() AS Exception
		SELF:_dbfError( ex, ERDD.OPEN_FILE, XSharp.Gencode.EG_OPEN )
	ENDIF
	IF SELF:_Ansi
		SELF:_lockScheme:Initialize( DbfLockingModel.VoAnsi )
	ELSE
		SELF:_lockScheme:Initialize( DbfLockingModel.Clipper52 )
	ENDIF
	
    //
RETURN isOK

    // Read the DBF Header, retrieve RecCount, then read the Fields Header
PRIVATE METHOD _readHeader() AS LOGIC
	LOCAL isOK AS LOGIC
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
    isOK := SELF:_Header:Read(SELF:_hFile)
    //
	IF isOK 
		SELF:_HeaderLength := SELF:_Header:HeaderLen
        //
		LOCAL fieldCount := (( SELF:_HeaderLength - DbfHeader.SIZE) / DbfField.SIZE ) AS INT
        // Something wrong in Size...
		IF fieldCount <= 0 
			RETURN FALSE
		ENDIF
		SELF:_RecCount := SELF:_Header:RecCount
        SELF:_Encoding := System.Text.Encoding.GetEncoding( CodePageExtensions.ToCodePage( SELF:_Header:CodePage )  )

        // Move to top, after header
        isOK := FSeek3( SELF:_hFile, DbfHeader.SIZE, SeekOrigin.Begin ) == DbfHeader.SIZE 
		IF isOK 
			isOK := _readFieldsHeader()
		ENDIF
	ENDIF
RETURN isOK

    // Read the Fields Header, filling the _Fields List with RddFieldInfo
PRIVATE METHOD _readFieldsHeader() AS LOGIC
	LOCAL isOK AS LOGIC
	LOCAL fieldCount := (( SELF:_HeaderLength - DbfHeader.SIZE) / DbfField.SIZE ) AS INT
	LOCAL fieldDefSize := fieldCount * DbfField.SIZE AS INT
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	SELF:_NullCount := 0
    // Read full Fields Header
	VAR fieldsBuffer := BYTE[]{ fieldDefSize }
    isOK := FRead3( SELF:_hFile, fieldsBuffer, (DWORD)fieldDefSize ) == (DWORD)fieldDefSize 
	IF isOK 
		SELF:_HasMemo := FALSE
		VAR currentField := DbfField{}
        currentField:Encoding := SELF:_Encoding
		currentField:initialize()
        // Now, process
        //SELF:_Fields := DbfRddFieldInfo[]{ fieldCount }
        // count # of fields. When we see a 0x0D then the header has blank space for non fields
		fieldCount := 0
		FOR VAR i := 0 UPTO fieldDefSize - 1 STEP DbfField.SIZE
			IF fieldsBuffer[i] == 0x0D // last field
				EXIT
			ENDIF
			fieldCount++
		NEXT
		
		SELF:SetFieldExtent( fieldCount )
		LOCAL nStart AS INT
		nStart := 0
		FOR VAR i := nStart TO fieldCount - ( 1 - nStart )
			local nPos := i*DbfField.SIZE as LONG
			Array.Copy(fieldsBuffer, nPos, currentField:Buffer, 0, DbfField.SIZE )
			IF ! SELF:Header:Version:UsesFlags()
			   currentField:ClearFlags()
			ENDIF
			VAR column := DbfColumn.Create(REF currentField, SELF, nPos + DbfHeader.SIZE)
			SELF:AddField( column)
			IF column:IsMemo
				SELF:_HasMemo := TRUE
			ENDIF
		NEXT
        // Allocate the Buffer to read Records
		SELF:_RecordLength := SELF:_Header:RecordLen
		SELF:_AllocateBuffers()
	ENDIF
RETURN isOK

INTERNAL METHOD _readField(nOffSet as LONG, oField as DbfField) AS LOGIC
    // Read single field. Called from AutoIncrement code to read the counter value
	local nPos as LONG
	nPos := (LONG) FTell(SELF:_hFile)
	FSeek3(SELF:_hFile, nOffSet, FS_SET)
	FRead3(SELF:_hFile, oField:Buffer, (DWORD) oField:Buffer:Length)
	FSeek3(SELF:_hFile, nPos, FS_SET)
RETURN TRUE

INTERNAL METHOD _writeField(nOffSet as LONG, oField as DbfField) AS LOGIC
	local nPos as LONG
    // Write single field in header. Called from AutoIncrement code to update the counter value
	nPos := (LONG) FTell(SELF:_hFile)
	FSeek3(SELF:_hFile, nOffSet, FS_SET)
	FWrite3(SELF:_hFile, oField:Buffer, (DWORD) oField:Buffer:Length)
	FSeek3(SELF:_hFile, nPos, FS_SET)
RETURN TRUE



    // Write the DBF file Header : Last DateTime of modification (now), Current Reccount
PROTECTED METHOD _writeHeader() AS LOGIC
	LOCAL ret := TRUE AS LOGIC
    // Really ?
	IF SELF:_Header:isHot 
		IF SELF:_ReadOnly 
            // Error !! Cannot be written !
			SELF:_dbfError( ERDD.READONLY, XSharp.Gencode.EG_READONLY )
			RETURN FALSE
		ENDIF
        // Update the number of records
		SELF:_Header:RecCount := SELF:_RecCount
		TRY
            ret := SELF:_Header:Write(SELF:_hFile)
		CATCH ex AS Exception
			SELF:_dbfError( ex, ERDD.WRITE, XSharp.Gencode.EG_WRITE )
			ret := FALSE
		END TRY
        // Ok, go Cold
		SELF:_Header:isHot := FALSE
	ENDIF
    //
RETURN ret


    // Fields
/// <inheritdoc />
METHOD SetFieldExtent( fieldCount AS LONG ) AS LOGIC
	SELF:_HasMemo := FALSE
RETURN SUPER:SetFieldExtent(fieldCount)


    // Add a Field to the _Fields List. Fields are added in the order of method call
    /// <inheritdoc />
METHOD AddField(info AS RddFieldInfo) AS LOGIC
	LOCAL isOK AS LOGIC
    // convert RddFieldInfo to DBFColumn
	IF ! (info IS DbfColumn)
		info := DbfColumn.Create(info, SELF)
	ENDIF
	isOK := SUPER:AddField( info )
	IF isOK  .AND. info:IsMemo
		SELF:_HasMemo := TRUE
	ENDIF
RETURN isOK

PROTECT OVERRIDE METHOD _checkFields(info AS RddFieldInfo) AS LOGIC
    // FieldName
	info:Name := info:Name:ToUpper():Trim()
    IF String.Compare(info:Name, _NULLFLAGS,TRUE) == 0
        info:Name := _NULLFLAGS
    ENDIF
	IF info:Name:Length > 10 
		info:Name := info:Name:Substring(0,10)
	ENDIF
	IF ! info:Validate()
		SELF:_dbfError( ERDD.CORRUPT_HEADER, XSharp.Gencode.EG_ARG,"ValidateDbfStructure", i"Field '{info.Name}' is not valid"  )
		RETURN FALSE
	ENDIF
	VAR cType := Chr( (BYTE) info:FieldType)
	IF ! cType $ SELF:_AllowedFieldTypes
		SELF:_dbfError( ERDD.CORRUPT_HEADER, XSharp.Gencode.EG_ARG,"ValidateDbfStructure", i"Field Type '{cType}' for field '{info.Name}' is not allowed for RDD '{SELF:Driver}'" )
	ENDIF

RETURN TRUE


/// <inheritdoc />
METHOD FieldInfo(nFldPos AS LONG, nOrdinal AS LONG, oNewValue AS OBJECT) AS OBJECT
	LOCAL oResult := NULL AS OBJECT
	IF SELF:_FieldIndexValidate(nFldPos)
		BEGIN LOCK SELF
			
            //
			SWITCH nOrdinal
            // These are handled in the parent class and also take care of aliases etc.
			CASE DbFieldInfo.DBS_NAME
			CASE DbFieldInfo.DBS_CAPTION
			CASE DbFieldInfo.DBS_LEN
			CASE DbFieldInfo.DBS_DEC
			CASE DbFieldInfo.DBS_TYPE
			CASE DbFieldInfo.DBS_ALIAS
			CASE DbFieldInfo.DBS_COLUMNINFO
				oResult := SUPER:FieldInfo(nFldPos, nOrdinal, oNewValue)

			CASE DbFieldInfo.DBS_ISNULL
			CASE DbFieldInfo.DBS_COUNTER
			CASE DbFieldInfo.DBS_STEP
				oResult := NULL
				local oColumn as DbfColumn
				oColumn := SELF:_GetColumn(nFldPos)
				if oColumn != NULL
					
					IF nOrdinal == DbFieldInfo.DBS_ISNULL
						oResult := oColumn:IsNull()
					ELSEIF nOrdinal == DbFieldInfo.DBS_COUNTER
						if oColumn IS DbfAutoIncrementColumn VAR dbfac
							dbfac:Read()
							oResult := dbfac:Counter
							if oNewValue != null
                                // update counter
								local iNewValue as Int32
								iNewValue := Convert.ToInt32(oNewValue)
								IF SELF:HeaderLock(DbLockMode.Lock)
									dbfac:Counter := iNewValue
									dbfac:Write()
									SELF:HeaderLock(DbLockMode.UnLock)
								ENDIF
							ENDIF
						ENDIF
					ELSEIF nOrdinal == DbFieldInfo.DBS_STEP
						if oColumn IS DbfAutoIncrementColumn VAR dbfac
							dbfac:Read()
							oResult := dbfac:IncrStep
							if oNewValue != null
                                // update step
								local iNewValue as Int32
								iNewValue := Convert.ToInt32(oNewValue)
								IF SELF:HeaderLock(DbLockMode.Lock)
									dbfac:IncrStep := iNewValue
									dbfac:Write()
									SELF:HeaderLock(DbLockMode.UnLock)
								ENDIF
							ENDIF
						ENDIF
					ENDIF
				ENDIF
				
			OTHERWISE
                // Everything falls through to parent at this moment
				oResult := SUPER:FieldInfo(nFldPos, nOrdinal, oNewValue)
			END SWITCH
		END LOCK
	ENDIF
RETURN oResult


    // Read & Write

// Move to the current record, then read the raw Data into the internal RecordBuffer; Set the DELETED Flag
VIRTUAL PROTECTED METHOD _readRecord() AS LOGIC
	LOCAL isOK AS LOGIC
    // Buffer is supposed to be correct
	IF SELF:_BufferValid == TRUE .OR. SELF:EoF
		RETURN TRUE
	ENDIF
    // File Ok ?
	isOK := SELF:IsOpen
    //
	IF  isOK 
        // Record pos is One-Based
		LOCAL lOffset := SELF:_HeaderLength + ( SELF:_RecNo - 1 ) * SELF:_RecordLength AS LONG
		isOK := ( FSeek3( SELF:_hFile, lOffset, FS_SET ) == lOffset )
		IF isOK 
            // Read Record
			isOK := ( FRead3( SELF:_hFile, SELF:_RecordBuffer, (DWORD)SELF:_RecordLength ) == (DWORD)SELF:_RecordLength )
			IF isOK 
				SELF:_BufferValid := TRUE
				SELF:_isValid := TRUE
				SELF:_Deleted := ( SELF:_RecordBuffer[ 0 ] == '*' )
            ELSE
               NOP 
            ENDIF
        ELSE
            NOP
		ENDIF
	ENDIF
RETURN isOK

    // Move to the current record, write the raw Data, then update the Header (for DateTime mainly)
VIRTUAL PROTECTED METHOD _writeRecord() AS LOGIC
	LOCAL isOK AS LOGIC
    // File Ok ?
	isOK := SELF:IsOpen
    //
	IF isOK 
    //
		IF SELF:_ReadOnly 
        // Error !! Cannot be written !
			SELF:_dbfError( ERDD.READONLY, XSharp.Gencode.EG_READONLY )
			isOK := FALSE
		ELSE
            SELF:_wasChanged := TRUE
            // Write Current Data Buffer
            // Record pos is One-Based
			LOCAL recordPos AS LONG
			
			recordPos := SELF:_HeaderLength + ( SELF:_RecNo - 1 ) * SELF:_RecordLength
			isOK := ( FSeek3( SELF:_hFile, recordPos, FS_SET ) == recordPos )
			IF isOK
			   // Write Record
				TRY
					FWrite3( SELF:_hFile, SELF:_RecordBuffer, (DWORD)SELF:_RecordLength )
			                // Don't forget to Update Header
					SELF:_Header:isHot := TRUE
					IF SELF:Shared 
						SELF:_writeHeader()
                        			FFlush(SELF:_hFile, TRUE)
					ENDIF
				CATCH ex AS Exception
					SELF:_dbfError( ex, ERDD.WRITE, XSharp.Gencode.EG_WRITE )
				END TRY
			ENDIF
		ENDIF
	ENDIF
RETURN isOK


INTERNAL METHOD _dbfError(ex AS Exception, iSubCode AS DWORD, iGenCode AS DWORD) AS VOID
	SELF:_dbfError(ex, iSubCode, iGenCode, String.Empty, ex?:Message, XSharp.Severity.ES_ERROR)
	
INTERNAL METHOD _dbfError(iSubCode AS DWORD, iGenCode AS DWORD) AS VOID
	SELF:_dbfError(NULL, iSubCode, iGenCode, String.Empty, String.Empty, XSharp.Severity.ES_ERROR)
	
INTERNAL METHOD _dbfError(ex AS Exception,iSubCode AS DWORD, iGenCode AS DWORD, iSeverity AS DWORD) AS VOID
	SELF:_dbfError(ex, iSubCode, iGenCode, String.Empty, String.Empty, iSeverity)
	
INTERNAL METHOD _dbfError(iSubCode AS DWORD, iGenCode AS DWORD, iSeverity AS DWORD) AS VOID
	SELF:_dbfError(NULL, iSubCode, iGenCode, String.Empty, String.Empty, iSeverity)
	
INTERNAL METHOD _dbfError(iSubCode AS DWORD, iGenCode AS DWORD, strFunction AS STRING) AS VOID
	SELF:_dbfError(NULL, iSubCode, iGenCode, strFunction, String.Empty, XSharp.Severity.ES_ERROR)
	
INTERNAL METHOD _dbfError(ex AS Exception, iSubCode AS DWORD, iGenCode AS DWORD, strFunction AS STRING) AS VOID
	SELF:_dbfError(ex, iSubCode, iGenCode, strFunction, String.Empty, XSharp.Severity.ES_ERROR)
	
INTERNAL METHOD _dbfError(iSubCode AS DWORD, iGenCode AS DWORD, strFunction AS STRING, strMessage AS STRING) AS VOID
	SELF:_dbfError(NULL, iSubCode, iGenCode, strFunction,strMessage, XSharp.Severity.ES_ERROR)
	
INTERNAL METHOD _dbfError(ex AS Exception, iSubCode AS DWORD, iGenCode AS DWORD, strFunction AS STRING, strMessage AS STRING, iSeverity AS DWORD) AS VOID
	LOCAL oError AS RddError
    //
	IF ex != NULL
		oError := RddError{ex,iGenCode, iSubCode}
	ELSE
		oError := RddError{iGenCode, iSubCode}
	ENDIF
	oError:SubSystem := SELF:Driver
	oError:Severity := iSeverity
	oError:FuncSym  := IIF(strFunction == NULL, "", strFunction) // code in the SDK expects all string properties to be non-NULL
	oError:FileName := SELF:_FileName
	IF String.IsNullOrEmpty(strMessage)  .AND. ex != NULL
		strMessage := ex:Message
    ENDIF
    IF String.IsNullOrEmpty(strMessage)
        IF oError:SubCode != 0
            oError:Description := oError:GenCodeText + " (" + oError:SubCodeText+")"
        ELSE
            oError:Description := oError:GenCodeText 
        ENDIF
    ELSE
	    oError:Description := strMessage
    ENDIF
	RuntimeState.LastRddError := oError
    //
	THROW oError
	
INTERNAL METHOD _getUsualType(oValue AS OBJECT) AS __UsualType
	LOCAL typeCde AS TypeCode
	IF oValue == NULL
		RETURN __UsualType.Void
	ELSE
		typeCde := Type.GetTypeCode(oValue:GetType())
		SWITCH typeCde
		CASE TypeCode.SByte
		CASE TypeCode.Byte
		CASE TypeCode.Int16
		CASE TypeCode.UInt16
		CASE TypeCode.Int32
			RETURN __UsualType.Long
		CASE TypeCode.UInt32
		CASE TypeCode.Int64
		CASE TypeCode.UInt64
		CASE TypeCode.Single
		CASE TypeCode.Double
			RETURN __UsualType.Float
		CASE TypeCode.Boolean
			RETURN __UsualType.Logic
		CASE TypeCode.String
			RETURN __UsualType.String
		CASE TypeCode.DateTime
			RETURN __UsualType.DateTime
		CASE TypeCode.Object
			IF oValue IS IDate
				RETURN __UsualType.Date
			ELSEIF  oValue IS IFloat
				RETURN __UsualType.Float
			ENDIF
		END SWITCH
	ENDIF
RETURN __UsualType.Object


INTERNAL VIRTUAL METHOD _GetColumn(nFldPos AS LONG) AS DbfColumn
	LOCAL nArrPos := nFldPos -1 AS LONG
    IF nArrPos >= 0 .AND. nArrPos < SELF:_Fields:Length
        RETURN (DbfColumn) SELF:_Fields[ nArrPos ]
    ENDIF
    SELF:_dbfError(EDB_FIELDINDEX, EG_ARG)
    RETURN NULL

    // Indicate if a Field is a Memo
    // At DBF Level, TRUE only for DbFieldType.Memo
INTERNAL VIRTUAL METHOD _isMemoField( nFldPos AS LONG ) AS LOGIC
	VAR oColumn := SELF:_GetColumn(nFldPos)
    IF oColumn != NULL
        RETURN oColumn:IsMemo
    ENDIF
    RETURN FALSE

    // Retrieve the BlockNumber as it is written in the DBF
OVERRIDE METHOD _getMemoBlockNumber( nFldPos AS LONG ) AS LONG
	LOCAL blockNbr := 0 AS LONG
	SELF:ForceRel()
	VAR oColumn := SELF:_GetColumn(nFldPos)
	IF oColumn != NULL .AND. oColumn:IsMemo
		IF SELF:_readRecord()
            VAR blockNo := oColumn:GetValue(SELF:_RecordBuffer)
            IF blockNo != NULL
			    blockNbr := (LONG) blockNo
            ENDIF
		ENDIF
	ENDIF
RETURN blockNbr

    /// <inheritdoc />
METHOD GetValue(nFldPos AS LONG) AS OBJECT
	LOCAL ret := NULL AS OBJECT
	SELF:ForceRel()
    // Read Record to Buffer
	VAR oColumn := SELF:_GetColumn(nFldPos)
    IF oColumn == NULL
        // Getcolumn already sets the error
        RETURN NULL
    ENDIF
	IF SELF:_readRecord()
        //
		IF oColumn:IsMemo
			IF SELF:HasMemo
                // At this level, the return value is the raw Data, in BYTE[]
				RETURN _Memo:GetValue(nFldPos)
			ELSE
				RETURN SUPER:GetValue(nFldPos)
			ENDIF
		ELSE
			ret := oColumn:GetValue(SELF:_RecordBuffer )
		ENDIF
	ELSE
		IF SELF:EoF 
            // do not call _Memo for empty values. Memo columns return an empty string for the empty value
			ret := oColumn:EmptyValue()
		ELSE
			SELF:_dbfError( Subcodes.ERDD_READ, XSharp.Gencode.EG_READ ,"DBF.GetValue")
		ENDIF
	ENDIF
RETURN ret

    /// <inheritdoc />
METHOD GetValueFile(nFldPos AS LONG, fileName AS STRING) AS LOGIC
	SELF:ForceRel()
	IF SELF:HasMemo
		RETURN _Memo:GetValueFile(nFldPos, fileName)
	ELSE
		RETURN SUPER:GetValueFile(nFldPos, fileName)
	ENDIF
	
    /// <inheritdoc />
METHOD GetValueLength(nFldPos AS LONG) AS LONG
	SELF:ForceRel()
	IF SELF:HasMemo
		RETURN _Memo:GetValueLength(nFldPos)
	ELSE
		RETURN SUPER:GetValueLength(nFldPos)
	ENDIF
	
    /// <inheritdoc />
METHOD Flush() 			AS LOGIC
	LOCAL isOK AS LOGIC
    LOCAL locked := FALSE AS LOGIC
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	IF SELF:_ReadOnly 
        // Error !! Cannot be written !
		SELF:_dbfError( ERDD.READONLY, XSharp.Gencode.EG_READONLY )
		RETURN FALSE
	ENDIF
	isOK := SELF:GoCold()

	IF isOK .and. SELF:_wasChanged
		IF SELF:Shared 
			locked := SELF:HeaderLock( DbLockMode.Lock )
            // Another workstation may have added another record, so make sure we update the reccount
            SELF:_RecCount := SELF:_calculateRecCount()
            //? SELF:CurrentThreadId, "After CalcReccount"
        ENDIF
		SELF:_putEndOfFileMarker()
        //? SELF:CurrentThreadId, "After EOF"
		SELF:_writeHeader()
        //? SELF:CurrentThreadId, "After writeHeader"
    	FFlush( SELF:_hFile )
        //? SELF:CurrentThreadId, "After FFlush"
	ENDIF
	IF SELF:Shared .AND. locked
		SELF:HeaderLock( DbLockMode.UnLock )
	ENDIF
    //
	IF SELF:HasMemo
		isOK := _Memo:Flush()
	ENDIF
RETURN isOK

    /// <inheritdoc />
METHOD Refresh() 			AS LOGIC
	LOCAL isOK AS LOGIC
	IF ! SELF:IsOpen
		RETURN FALSE
	ENDIF
	IF SELF:_ReadOnly 
		RETURN TRUE
	ENDIF
	SELF:_Hot := FALSE
	SELF:_BufferValid := FALSE
	IF SELF:_NewRecord 
		SELF:_NewRecord  := FALSE
		isOK := SELF:GoBottom()
	ELSE
		isOK := TRUE
	ENDIF
    //
RETURN isOK	
    // Save any Pending Change
    /// <inheritdoc />
METHOD GoCold()			AS LOGIC
	LOCAL ret AS LOGIC
    //
	ret := TRUE
	IF SELF:_Hot 
		BEGIN LOCK SELF
            //? CurrentThreadId, "GoCold Recno", SELF:RecNo
			SELF:_writeRecord()
			SELF:_NewRecord := FALSE
			SELF:_Hot := FALSE
		END LOCK
	ENDIF
RETURN ret

    // Indicate that the content of the current buffer needs to be saved
    /// <inheritdoc />
METHOD GoHot()			AS LOGIC
	LOCAL ret AS LOGIC
    //
	ret := TRUE
	IF !SELF:_Hot 
		BEGIN LOCK SELF
			IF SELF:_Shared .AND. !SELF:_fLocked .AND. !SELF:_Locks:Contains( SELF:RecNo )
				SELF:_dbfError( ERDD.UNLOCKED, XSharp.Gencode.EG_UNLOCKED )
				ret := FALSE
			ENDIF
			IF SELF:_ReadOnly 
            // Error !! Cannot be written !
				SELF:_dbfError( ERDD.READONLY, XSharp.Gencode.EG_READONLY )
				ret := FALSE
			ELSE
				SELF:_Hot := TRUE
			ENDIF
		END LOCK
	ENDIF
RETURN ret

/// <summary>Is the current row </summary>
PROPERTY IsHot AS LOGIC GET SELF:_Hot
/// <summary>Is the current row a new record (the result of Append())</summary>
PROPERTY IsNewRecord AS LOGIC GET SELF:_NewRecord
	
/// <inheritdoc />
METHOD PutValue(nFldPos AS LONG, oValue AS OBJECT) AS LOGIC
    LOCAL ret := FALSE AS LOGIC
    IF SELF:_ReadOnly
        SELF:_dbfError(ERDD.READONLY, XSharp.Gencode.EG_READONLY )
    ENDIF
    IF SELF:EoF
        RETURN FALSE
    ENDIF
    SELF:ForceRel()
	IF SELF:_readRecord()
        // GoHot() must be called first because this saves the current index values
    	ret := TRUE
		IF ! SELF:_Hot
			SELF:GoHot()
		ENDIF
		VAR oColumn := SELF:_GetColumn(nFldPos)
        IF oColumn != NULL
		    IF oColumn:IsMemo
			    IF SELF:HasMemo
				    IF _Memo:PutValue(nFldPos, oValue)
                        // Update the Field Info with the new MemoBlock Position
					    oColumn:PutValue(SELF:Memo:LastWrittenBlockNumber, SELF:_RecordBuffer)
				    ENDIF
			    ELSE
				    ret := SUPER:PutValue(nFldPos, oValue)
			    ENDIF
		    ELSE
			    ret := oColumn:PutValue(oValue, SELF:_RecordBuffer)
            ENDIF
        ELSE
            // Getcolumn already sets the error
            RETURN FALSE
        ENDIF
    ENDIF
    IF ! ret
        SELF:_dbfError(Subcodes.ERDD_WRITE, Gencode.EG_WRITE,"DBF.PutValue")
    ENDIF
RETURN ret

    /// <inheritdoc />
METHOD PutValueFile(nFldPos AS LONG, fileName AS STRING) AS LOGIC
    IF SELF:_ReadOnly
        SELF:_dbfError(ERDD.READONLY, XSharp.Gencode.EG_READONLY )
    ENDIF
    IF SELF:EoF
        RETURN FALSE
    ENDIF
    IF SELF:HasMemo
		RETURN _Memo:PutValueFile(nFldPos, fileName)
	ELSE
		RETURN SUPER:PutValue(nFldPos, fileName)
	ENDIF
	
	
    // Locking
    //	METHOD AppendLock(uiMode AS DbLockMode) AS LOGIC
    //	METHOD HeaderLock(uiMode AS DbLockMode) AS LOGIC
    //	METHOD Lock(uiMode AS DbLockMode) AS LOGIC
    //	METHOD UnLock(oRecId AS OBJECT) AS LOGIC
	
    // Memo File Access
    /// <inheritdoc />
METHOD CloseMemFile() 	AS LOGIC
	IF SELF:HasMemo
		RETURN _Memo:CloseMemFile()
	ELSE
		RETURN SUPER:CloseMemFile()
	ENDIF
    /// <inheritdoc />
METHOD CreateMemFile(info AS DbOpenInfo) 	AS LOGIC
	IF SELF:HasMemo
		RETURN _Memo:CreateMemFile(info)
	ELSE
		RETURN SUPER:CreateMemFile(info)
	ENDIF
	
    /// <inheritdoc />
METHOD OpenMemFile(info AS DbOpenInfo) 	AS LOGIC
	IF SELF:HasMemo
		RETURN _Memo:OpenMemFile(info)
	ELSE
		RETURN SUPER:OpenMemFile(info)
	ENDIF
	
    // Indexes
	
    /// <inheritdoc />
METHOD OrderCreate(info AS DbOrderCreateInfo) AS LOGIC
	IF _oIndex != NULL
		RETURN _oIndex:OrderCreate(info)
	ELSE
		RETURN SUPER:OrderCreate(info)
	ENDIF
	
    /// <inheritdoc />
METHOD OrderDestroy(info AS DbOrderInfo) AS LOGIC
	IF _oIndex != NULL
		RETURN _oIndex:OrderDestroy(info)
	ELSE
		RETURN SUPER:OrderDestroy(info)
	ENDIF
	
    /// <inheritdoc />
METHOD OrderInfo(nOrdinal AS DWORD, info AS DbOrderInfo) AS OBJECT
	IF _oIndex != NULL
		RETURN _oIndex:OrderInfo(nOrdinal,info )
	ELSE
		RETURN SUPER:OrderInfo(nOrdinal,info )
	ENDIF
	
    /// <inheritdoc />
METHOD OrderListAdd(info AS DbOrderInfo) AS LOGIC
	IF _oIndex != NULL
		RETURN _oIndex:OrderListAdd(info)
	ELSE
		RETURN SUPER:OrderListAdd(info)
	ENDIF
	
    /// <inheritdoc />
METHOD OrderListDelete(info AS DbOrderInfo) AS LOGIC
	IF _oIndex != NULL
		RETURN _oIndex:OrderListDelete(info)
	ELSE
		RETURN SUPER:OrderListDelete(info)
	ENDIF
    /// <inheritdoc />
METHOD OrderListFocus(info AS DbOrderInfo) AS LOGIC
	IF _oIndex != NULL
		RETURN _oIndex:OrderListFocus(info)
	ELSE
		RETURN SUPER:OrderListFocus(info)
	ENDIF
    /// <inheritdoc />
METHOD OrderListRebuild() AS LOGIC
	IF _oIndex != NULL
		RETURN _oIndex:OrderListRebuild()
	ELSE
		RETURN SUPER:OrderListRebuild()
	ENDIF
    /// <inheritdoc />
METHOD Seek(info AS DbSeekInfo) AS LOGIC
    LOCAL result as LOGIC
	IF _oIndex != NULL
		result := _oIndex:Seek(info)
	ELSE
		result := SUPER:Seek(info)
    ENDIF
    SELF:_CheckEofBof()
    RETURN result
	
    // Relations
    /// <inheritdoc />
METHOD ChildEnd(info AS DbRelInfo) AS LOGIC
	SELF:ForceRel()
RETURN SUPER:ChildEnd( info )

    /// <inheritdoc />
METHOD ChildStart(info AS DbRelInfo) AS LOGIC
	SELF:ChildSync( info )
RETURN SUPER:ChildStart( info )

    /// <inheritdoc />
METHOD ChildSync(info AS DbRelInfo) AS LOGIC
	SELF:GoCold()
	SELF:_RelInfoPending := info
	SELF:SyncChildren()
RETURN TRUE

    /// <inheritdoc />
METHOD ForceRel() AS LOGIC
	LOCAL isOK    := TRUE AS LOGIC
	LOCAL gotoRec := 0 AS LONG
	IF SELF:_RelInfoPending != NULL
    // Save the current context
		LOCAL currentRelation := SELF:_RelInfoPending AS DbRelInfo
		SELF:_RelInfoPending := NULL
    //
		isOK := SELF:RelEval( currentRelation )
		IF isOK .AND. !((DBF)currentRelation:Parent):EoF
			TRY
				gotoRec := Convert.ToInt32( SELF:_EvalResult )
			CATCH ex AS InvalidCastException
				gotoRec := 0
				SELF:_dbfError(ex, Subcodes.ERDD_DATATYPE,Gencode.EG_DATATYPE,  "DBF.ForceRel") 
				
			END TRY
		ENDIF
		isOK := SELF:GoTo( gotoRec )
		SELF:_Found := SELF:_isValid
		SELF:_SetBOF(FALSE)
	ENDIF
RETURN isOK


    /// <inheritdoc />
METHOD RelArea(nRelNum AS DWORD) AS DWORD
RETURN SUPER:RelArea(nRelNum)

    /// <inheritdoc />
METHOD SyncChildren() AS LOGIC
	LOCAL isOK AS LOGIC
    //
	isOK := TRUE
	FOREACH info AS DbRelInfo IN SELF:_Relations
		isOK := info:Child:ChildSync( info )
		IF !isOK
			EXIT
		ENDIF
	NEXT
RETURN isOK



    // Codeblock Support
/// <inheritdoc />
VIRTUAL METHOD Compile(sBlock AS STRING) AS ICodeblock
	LOCAL result AS ICodeblock
	result := SUPER:Compile(sBlock)
	IF result == NULL
        var msg := "Could not compile epression '"+sBlock+"'"
        if (RuntimeState:LastRddError != NULL_OBJECT)
            msg += "("+RuntimeState:LastRddError:Message+")"
        ENDIF
		SELF:_dbfError( Subcodes.EDB_EXPRESSION, Gencode.EG_SYNTAX,"DBF.Compile", msg )
	ENDIF
RETURN result

/// <inheritdoc />
VIRTUAL METHOD EvalBlock( cbBlock AS ICodeblock ) AS OBJECT
	LOCAL result := NULL AS OBJECT
	TRY
		result := SUPER:EvalBlock(cbBlock)
	CATCH ex AS Exception
		SELF:_dbfError(ex, Subcodes.EDB_EXPRESSION, Gencode.EG_SYNTAX, "DBF.EvalBlock")
	END TRY
RETURN result

    // Other
    /// <inheritdoc />
VIRTUAL METHOD Info(nOrdinal AS INT, oNewValue AS OBJECT) AS OBJECT
	LOCAL oResult AS OBJECT
	oResult := NULL
	SWITCH nOrdinal
	CASE DbInfo.DBI_ISDBF
	CASE DbInfo.DBI_CANPUTREC
		oResult := IIF(SELF:HasMemo, FALSE , TRUE)
	CASE DbInfo.DBI_GETRECSIZE
		oResult := SELF:_RecordLength
	CASE DbInfo.DBI_LASTUPDATE
		oResult := SELF:_Header:LastUpdate
	CASE DbInfo.DBI_GETHEADERSIZE
		oResult := (LONG) SELF:_Header:HeaderLen
	CASE DbInfo.DBI_CODEPAGE
	CASE DbInfo.DBI_DOSCODEPAGE
	CASE DbInfo.DBI_CODEPAGE_HB
        // DOS or Windows codepage based on DBF Codepage
		oResult := (INT) SELF:_Header:CodePage:ToCodePage()
		
	CASE DbInfo.DBI_GETLOCKARRAY
		VAR aLocks := SELF:_Locks:ToArray()
		System.Array.Sort(aLocks)
		oResult := aLocks
		
	CASE DbInfo.DBI_LOCKCOUNT
		oResult := SELF:_Locks:Count
	CASE DbInfo.DBI_LOCKOFFSET
		oResult := SELF:_lockScheme:Offset
		
	CASE DbInfo.DBI_FILEHANDLE
		oResult := SELF:_hFile
	CASE DbInfo.DBI_FULLPATH
		oResult := SELF:_FileName
	CASE DbInfo.DBI_TABLEEXT
		IF SELF:_FileName != NULL
			oResult := System.IO.Path.GetExtension(SELF:_FileName)
		ELSE
			oResult := _Extension
		ENDIF
		IF oNewValue IS STRING
			_Extension := (STRING) oNewValue
		ENDIF
		
	CASE DbInfo.DBI_SHARED
		oResult := SELF:Shared 
		
	CASE DbInfo.DBI_READONLY
	CASE DbInfo.DBI_ISREADONLY
		oResult := SELF:_ReadOnly
		
	CASE DbInfo.DBI_ISANSI
		oResult := SELF:_Ansi
		
		
	CASE DbInfo.DBI_ISFLOCK
		oResult := SELF:_fLocked
		
	CASE DbInfo.DBI_MEMOHANDLE
		oResult := IntPtr.Zero      // Should be handled in the memo subclass
	CASE DbInfo.DBI_MEMOEXT
		oResult := ""               // Should be handled in the memo subclass
	CASE DbInfo.DBI_MEMOBLOCKSIZE
		oResult := 0
	CASE DbInfo.DBI_MEMOFIELD
		oResult := ""
    // DbInfo.TRANSREC
	CASE DbInfo.DBI_VALIDBUFFER
		oResult := SELF:_BufferValid
        // CASE DbInfo.DBI_POSITIONED
		
	CASE DbInfo.DBI_OPENINFO
		oResult := SELF:_OpenInfo
		
	CASE DbInfo.DBI_DB_VERSION
	CASE DbInfo.DBI_RDD_VERSION
		LOCAL oAsm AS System.Reflection.AssemblyName
		LOCAL oType AS System.Type
		oType := typeof(DBF)
		oAsm := oType:Assembly:GetName()
		RETURN oAsm:Version:ToString()
		
        // Harbour extensions. Some are supported. Other not yet
    // case DbInfo.DBI_ISREADONLY
	CASE DbInfo.DBI_LOCKSCHEME
		RETURN 0
	CASE DbInfo.DBI_ROLLBACK
		IF SELF:_Hot
			IF SELF:_NewRecord
				Array.Copy(SELF:_BlankBuffer, SELF:_RecordBuffer, SELF:_RecordLength)
				SELF:_Deleted := FALSE
			ELSE
				SELF:_BufferValid := FALSE
			ENDIF
			SELF:_Hot := FALSE
		ENDIF
	CASE DbInfo.DBI_PASSWORD
		oResult := NULL             
	CASE DbInfo.DBI_ISENCRYPTED     
		oResult := FALSE
	CASE DbInfo.DBI_MEMOTYPE
		oResult := DB_MEMO_NONE
	CASE DbInfo.DBI_SEPARATOR
		oResult := ""
	CASE DbInfo.DBI_MEMOVERSION
		oResult := 0
	CASE DbInfo.DBI_TABLETYPE
		oResult := 0
	CASE DbInfo.DBI_SCOPEDRELATION
		oResult := FALSE
	CASE DbInfo.DBI_TRIGGER
		oResult := NULL     // Todo
	CASE DbInfo.DBI_DECRYPT         // Todo
	CASE DbInfo.DBI_ENCRYPT         // Todo
	CASE DbInfo.DBI_MEMOPACK
	CASE DbInfo.DBI_DIRTYREAD
	CASE DbInfo.DBI_POSITIONED
	CASE DbInfo.DBI_ISTEMPORARY
	CASE DbInfo.DBI_LOCKTEST
	CASE DbInfo.DBI_TRANSREC
	CASE DbInfo.DBI_SETHEADER
        //CASE DbInfo.DBI_CODEPAGE_HB    // defined above
	CASE DbInfo.DBI_RM_SUPPORTED
	CASE DbInfo.DBI_RM_CREATE
	CASE DbInfo.DBI_RM_REMOVE
	CASE DbInfo.DBI_RM_CLEAR 
	CASE DbInfo.DBI_RM_FILL  
	CASE DbInfo.DBI_RM_ADD   
	CASE DbInfo.DBI_RM_DROP  
	CASE DbInfo.DBI_RM_TEST  
	CASE DbInfo.DBI_RM_COUNT 
	CASE DbInfo.DBI_RM_HANDLE
		RETURN FALSE
	OTHERWISE
		oResult := SUPER:Info(nOrdinal, oNewValue)
	END SWITCH
RETURN oResult




/// <inheritdoc />
VIRTUAL METHOD RecInfo(nOrdinal AS LONG, oRecID AS OBJECT, oNewValue AS OBJECT) AS OBJECT
	LOCAL nNewRec := 0 AS LONG
	LOCAL oResult AS OBJECT
	LOCAL nOld := 0 AS LONG
	
	IF oRecID != NULL 
		TRY
			nNewRec := Convert.ToInt32( oRecID )
		CATCH ex AS Exception
			nNewRec := SELF:RecNo
			SELF:_dbfError(ex, Subcodes.ERDD_DATATYPE, Gencode.EG_DATATYPE, "DBF.RecInfo")
			
		END TRY
	ELSE
		nNewRec := SELF:RecNo
	ENDIF
	
    // Some operations require the new record te be selected
	SELF:ForceRel()
	IF nNewRec != 0
		SWITCH nOrdinal
		CASE DBRI_DELETED
		CASE DBRI_ENCRYPTED
		CASE DBRI_RAWRECORD
		CASE DBRI_RAWMEMOS
		CASE DBRI_RAWDATA
			nOld     := SELF:RecNo
			SELF:GoTo(nNewRec)
		END SWITCH
	ENDIF
	SWITCH nOrdinal
	CASE DBRI_DELETED
		oResult := SELF:Deleted
	CASE DBRI_LOCKED
		IF SELF:_Shared 
			IF nNewRec == 0
				nNewRec := SELF:RecNo
			ENDIF
			oResult := SELF:_Locks:Contains( nNewRec )
		ELSE
			oResult := TRUE
		ENDIF
	CASE DBRI_RECNO
		oResult := SELF:RecNo
	CASE DBRI_RECSIZE
		oResult := SELF:_RecordLength
	CASE DBRI_BUFFPTR
		SELF:_readRecord()
		oResult := SELF:_RecordBuffer
	CASE DBRI_RAWRECORD
		oResult := SELF:_Encoding:GetString(SELF:_RecordBuffer,0, SELF:_RecordLength)
	CASE DBRI_UPDATED
		oResult := SELF:_Hot
		IF oNewValue IS LOGIC VAR isNew
			IF isNew
				SELF:_BufferValid := FALSE
				SELF:_readRecord()
			ENDIF
		ENDIF
	CASE DBRI_RAWMEMOS
	CASE DBRI_RAWDATA
        // RawData returns a string with the record + memos
        // RawMemos returns just the memos
        // Todo
		oResult := ""
	CASE DBRI_ENCRYPTED
        // Todo
		oResult := FALSE
	OTHERWISE
		oResult := SUPER:Info(nOrdinal, oNewValue)
	END SWITCH
	IF nOld != 0
		SELF:GoTo(nOld)
	ENDIF
RETURN oResult

/// <inheritdoc />
METHOD Sort(info AS DbSortInfo) AS LOGIC
	LOCAL recordNumber AS LONG
	LOCAL trInfo AS DbTransInfo
	LOCAL hasWhile AS LOGIC
	LOCAL hasFor AS LOGIC
	LOCAL sort AS RddSortHelper
	LOCAL i AS DWORD
	LOCAL fieldPos AS LONG
	LOCAL isNum AS LONG
	LOCAL isOK AS LOGIC
	LOCAL isQualified AS LOGIC
	LOCAL readMore AS LOGIC
	LOCAL limit AS LOGIC
	LOCAL rec AS SortRecord
	LOCAL sc AS DBFSortCompare
    //
	recordNumber := 0
	trInfo := info:TransInfo
	trInfo:Scope:Compile(SELF)
	hasWhile := trInfo:Scope:WhileBlock != NULL
	hasFor   := trInfo:Scope:ForBlock != NULL
	sort := RddSortHelper{SELF, info, SELF:RecCount}
    // 
	i := 0
	WHILE i < info:Items:Length
		fieldPos := info:Items[i]:FieldNo
		isNum := 0
		IF SELF:_Fields[fieldPos]:FieldType == DbFieldType.Number 
			isNum := 2
			info:Items[i]:Flags |= isNum
		ENDIF
		info:Items[i]:OffSet := SELF:_Fields[fieldPos]:Offset
		info:Items[i]:Length := SELF:_Fields[fieldPos]:Length
        //Next Field
		i++
	ENDDO
	isOK := TRUE
	isQualified := TRUE
	readMore := TRUE
	limit := TRUE
    //
    //			IF ( SELF:_Relations:Count > 0)
    //				SELF:ForceRel()
    //			ENDIF
    //
	IF trInfo:Scope:RecId != NULL
		recordNumber := Convert.ToInt32(trInfo:Scope:RecId)
		isOK := SELF:GoTo(recordNumber)
		readMore := TRUE
		limit := TRUE
		recordNumber := 1
	ELSE
		IF trInfo:Scope:NextCount != 0
			limit := TRUE
			recordNumber := trInfo:Scope:NextCount
			IF recordNumber < 1
				readMore := FALSE
			ENDIF
		ELSE
			readMore := TRUE
			limit := FALSE
			IF trInfo:Scope:WhileBlock == NULL .AND. !trInfo:Scope:Rest
				isOK := SELF:GoTop()
			ENDIF
		ENDIF
	ENDIF
	WHILE isOK .AND. !SELF:EoF .AND. readMore
		IF hasWhile
			readMore := (LOGIC) SELF:EvalBlock(trInfo:Scope:WhileBlock)
		ENDIF
		IF readMore .AND. hasFor
			isQualified := (LOGIC) SELF:EvalBlock(trInfo:Scope:ForBlock)
		ELSE
			isQualified := readMore
		ENDIF
		IF isOK .AND. isQualified
			isOK := SELF:_readRecord()
			IF isOK
				rec := SortRecord{SELF:_RecordBuffer, SELF:_RecNo}
				isOK := sort:Add(rec)
			ENDIF
		ENDIF
		IF readMore .AND. limit
			readMore := (--recordNumber != 0)
		ENDIF
		IF isOK .AND. readMore
			isOK := SELF:Skip(1)
		ENDIF
	END WHILE
	IF isOK
		sc := DBFSortCompare{SELF, info}
		isOK := sort:Sort(sc)
	ENDIF
	IF isOK
		isOK := sort:Write(SELF)
	ENDIF
RETURN isOK            

    // IRddSortWriter Interface, used by RddSortHelper
METHOD IRddSortWriter.WriteSorted( sortInfo AS DbSortInfo , record AS SortRecord ) AS LOGIC
	Array.Copy(record:Data, SELF:_RecordBuffer, SELF:_RecordLength)
RETURN SELF:TransRec(sortInfo:TransInfo)


/// <inheritdoc />
VIRTUAL METHOD TransRec(info AS DbTransInfo) AS LOGIC
LOCAL result AS LOGIC
IF FALSE .AND. info:Destination IS DBF VAR oDest
    LOCAL oValue AS OBJECT
    result := oDest:Append(TRUE)
    IF info:Flags:HasFlag(DbTransInfoFlags.SameStructure)
        IF info:Flags:HasFlag(DbTransInfoFlags.CanPutRec) 
            VAR buffer  := SELF:GetRec()
            result      := oDest:PutRec(buffer)
        ELSE
            VAR buffer  := SELF:GetRec()
            result      := oDest:PutRec(buffer)
            FOR VAR nI := 1 TO SELF:FieldCount
                LOCAL oColumn AS DbfColumn
                oColumn := oDest:_GetColumn(nI)
                IF oColumn:IsMemo
                    oValue := SELF:GetValue(nI)
                    oColumn:PutValue(0, oDest:_RecordBuffer)
                    result := oDest:PutValue(nI, oValue)
                    IF ! result
                        EXIT
                    ENDIF
                ENDIF
            NEXT
        ENDIF
    ELSE
        FOREACH oItem AS DbTransItem IN info:Items
            oValue := SELF:GetValue(oItem:Source)
            result := oDest:PutValue(oItem:Destination, oValue)
            IF ! result
                EXIT
            ENDIF
        NEXT
    ENDIF
    IF result .AND. SELF:Deleted
        result := oDest:Delete()
    ENDIF
ELSE
    result := SUPER:TransRec(info)
ENDIF
RETURN result


INTERNAL METHOD Validate() AS VOID
	IF !SELF:_BufferValid 
		SELF:_readRecord()
	ENDIF			
    // Properties
    //	PROPERTY Alias 		AS STRING GET
    /// <inheritdoc />
PROPERTY BoF 		AS LOGIC
	GET 
		SELF:ForceRel()
		RETURN SUPER:BoF 
	END GET
END PROPERTY

/// <inheritdoc />
PROPERTY Deleted 	AS LOGIC 
	GET
		SELF:ForceRel()
		SELF:_readRecord()
		RETURN SELF:_Deleted
	END GET
END PROPERTY

/// <inheritdoc />
PROPERTY EoF 		AS LOGIC
	GET 
		SELF:ForceRel()
		RETURN SUPER:EoF 
	END GET
END PROPERTY

//PROPERTY Exclusive	AS LOGIC GET

/// <inheritdoc />
PROPERTY FieldCount AS LONG GET SELF:_Fields:Length
	
//	PROPERTY FilterText	AS STRING GET
PROPERTY Found		AS LOGIC
	GET 
		SELF:ForceRel()
		RETURN SUPER:Found
	END GET
END PROPERTY

/// <inheritdoc />
PROPERTY RecCount	AS LONG
	GET
		IF SELF:Shared 
			SELF:_RecCount := SELF:_calculateRecCount()
		ENDIF
		RETURN SELF:_RecCount
	END GET
END PROPERTY

PRIVATE METHOD _calculateRecCount()	AS LONG
	LOCAL reccount := 0 AS LONG
    //
	IF SELF:IsOpen
		VAR stream  := FGetStream(SELF:_hFile)
        VAR fSize   := stream:Length
		IF fSize != 0  // Just created file ?
			reccount := (LONG) ( fSize - SELF:_HeaderLength ) / SELF:_RecordLength
        ENDIF
	ENDIF
RETURN reccount

    /// <inheritdoc />
PROPERTY RecNo		AS INT
	GET
		SELF:ForceRel()
		RETURN SELF:_RecNo
	END GET
END PROPERTY

/// <inheritdoc />
VIRTUAL PROPERTY Driver AS STRING GET "DBF"
	
	
/// <summary>DBF Header.</summary>
CLASS DbfHeader
    // Fixed Buffer of 32 bytes
    // Matches the DBF layout
    // Read/Write to/from the Stream with the Buffer
    // and access individual values using the other fields
	
	PRIVATE CONST OFFSET_SIG			 := 0  AS BYTE
	PRIVATE CONST OFFSET_YEAR			 := 1  AS BYTE           // add 1900 so possible values are 1900 - 2155
	PRIVATE CONST OFFSET_MONTH	         := 2  AS BYTE
	PRIVATE CONST OFFSET_DAY             := 3  AS BYTE
	PRIVATE CONST OFFSET_RECCOUNT        := 4  AS BYTE
	PRIVATE CONST OFFSET_DATAOFFSET      := 8  AS BYTE
	PRIVATE CONST OFFSET_RECSIZE         := 10 AS BYTE
	PRIVATE CONST OFFSET_RESERVED1       := 12 AS BYTE
	PRIVATE CONST OFFSET_TRANSACTION     := 14 AS BYTE
	PRIVATE CONST OFFSET_ENCRYPTED       := 15 AS BYTE
	PRIVATE CONST OFFSET_DBASELAN        := 16 AS BYTE
	PRIVATE CONST OFFSET_MULTIUSER       := 20 AS BYTE
	PRIVATE CONST OFFSET_RESERVED2       := 24 AS BYTE
	PRIVATE CONST OFFSET_HASTAGS	     := 28 AS BYTE
	PRIVATE CONST OFFSET_CODEPAGE        := 29 AS BYTE
	PRIVATE CONST OFFSET_RESERVED3       := 30 AS BYTE
	INTERNAL CONST SIZE                  := 32 AS BYTE
	
	PUBLIC Buffer   AS BYTE[]
// Hot ?  => Header has changed ?
	PUBLIC isHot	AS LOGIC
	
PROPERTY Version    AS DBFVersion	;
    GET (DBFVersion) Buffer[OFFSET_SIG] ;
    SET Buffer[OFFSET_SIG] := (BYTE) value,isHot := TRUE
	
// Date of last update; in YYMMDD format.  Each byte contains the number as a binary.
// YY is added to a base of 1900 decimal to determine the actual year.
// Therefore, YY has possible values from 0x00-0xFF, which allows for a range from 1900-2155.
	
PROPERTY Year		AS LONG			
	GET
		LOCAL nYear AS LONG
		nYear := DateTime.Now:Year
		nYear := nYear - (nYear % 100)  // Get century
		RETURN Buffer[OFFSET_YEAR] + nYear
	END GET
	SET
		Buffer[OFFSET_YEAR] := (BYTE) (value% 100)
		isHot := TRUE
	END SET
END PROPERTY	
PROPERTY Month		AS BYTE			;
    GET Buffer[OFFSET_MONTH]	;
    SET Buffer[OFFSET_MONTH] := value, isHot := TRUE
	
PROPERTY Day		AS BYTE			;
    GET Buffer[OFFSET_DAY]	;
    SET Buffer[OFFSET_DAY] := value, isHot := TRUE
// Number of records in the table. (Least significant byte first.)		
PROPERTY RecCount	AS LONG			;
    GET BitConverter.ToInt32(Buffer, OFFSET_RECCOUNT) ;
    SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_RECCOUNT, SIZEOF(LONG)), isHot := TRUE
// Number of bytes in the header. (Least significant byte first.)
	
PROPERTY HeaderLen	AS SHORT		;
    GET BitConverter.ToInt16(Buffer, OFFSET_DATAOFFSET);
    SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_DATAOFFSET, SIZEOF(SHORT)), isHot := TRUE
	
// Length of one data record, including deleted flag
PROPERTY RecordLen	AS WORD		;
    GET BitConverter.ToUInt16(Buffer, OFFSET_RECSIZE);
    SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_RECSIZE, SIZEOF(WORD)), isHot := TRUE
	
// Reserved
PROPERTY Reserved1	AS SHORT		;
    GET BitConverter.ToInt16(Buffer, OFFSET_RESERVED1);
    SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_RESERVED1, SIZEOF(SHORT)), isHot := TRUE
	
// Flag indicating incomplete dBASE IV transaction.		
PROPERTY Transaction AS BYTE		;
    GET Buffer[OFFSET_TRANSACTION];
    SET Buffer[OFFSET_TRANSACTION] := value, isHot := TRUE
	
// dBASE IV encryption flag.		
PROPERTY Encrypted	AS BYTE			;
    GET Buffer[OFFSET_ENCRYPTED];
    SET Buffer[OFFSET_ENCRYPTED] := value, isHot := TRUE
	
PROPERTY DbaseLan	AS LONG			;
    GET BitConverter.ToInt32(Buffer, OFFSET_DBASELAN) ;
    SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_DBASELAN, SIZEOF(LONG)), isHot := TRUE
	
PROPERTY MultiUser	AS LONG			;
    GET BitConverter.ToInt32(Buffer, OFFSET_MULTIUSER)	;
    SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_MULTIUSER, SIZEOF(LONG)), isHot := TRUE
	
PROPERTY Reserved2	AS LONG			;
    GET BitConverter.ToInt32(Buffer, OFFSET_RESERVED2);
    SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_RESERVED2, SIZEOF(LONG))
	
PROPERTY HasTags	AS DBFTableFlags ;
    GET (DBFTableFlags)Buffer[OFFSET_HASTAGS] ;
    SET Buffer[OFFSET_HASTAGS] := (BYTE) value, isHot := TRUE
	
PROPERTY CodePage	AS DbfHeaderCodepage			 ;
    GET (DbfHeaderCodepage) Buffer[OFFSET_CODEPAGE]  ;
    SET Buffer[OFFSET_CODEPAGE] := (BYTE) value, isHot := TRUE
	
PROPERTY Reserved3	AS SHORT         ;
    GET BitConverter.ToInt16(Buffer, OFFSET_RESERVED3);
    SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_RESERVED3, SIZEOF(SHORT)), isHot := TRUE
	
// Note that the year property already does the 1900 offset calculation ! 
PROPERTY LastUpdate AS DateTime      ;  
    GET DateTime{Year, Month, Day} ;

	
PROPERTY IsAnsi AS LOGIC GET CodePage:IsAnsi()
	
METHOD initialize() AS VOID STRICT
	Buffer := BYTE[]{DbfHeader.SIZE}
	isHot  := FALSE
RETURN
    // Dbase (7?) Extends this with
    // [FieldOffSet(31)] PUBLIC LanguageDriverName[32]	 as BYTE
    // [FieldOffSet(63)] PUBLIC Reserved6 AS LONG
    /*
    0x02   FoxBASE
    0x03   FoxBASE+/Dbase III plus, no memo
    0x04   dBase 4
    0x05   dBase 5
    0x07   VO/Vulcan Ansi encoding
    0x13   FLagship dbv
    0x23   Flagship 2/4/8
    0x30   Visual FoxPro
    0x31   Visual FoxPro, autoincrement enabled
    0x33   Flagship 2/4/8 + dbv
    0x43   dBASE IV SQL table files, no memo
    0x63   dBASE IV SQL system files, no memo
    0x7B   dBASE IV, with memo
    0x83   FoxBASE+/dBASE III PLUS, with memo
    0x87   VO/Vulcan Ansi encoding with memo
    0x8B   dBASE IV with memo
    0xCB   dBASE IV SQL table files, with memo
    0xE5   Clipper SIX driver, with SMT memo
    0xF5   FoxPro 2.x (or earlier) with memo
    0xFB   FoxBASE
    
    FoxPro additional Table structure:
    28 	Table flags:
    0x01   file has a structural .cdx
    0x02   file has a Memo field
    0x04   file is a database (.dbc)
    This byte can contain the sum of any of the above values.
    For example, the value 0x03 indicates the table has a structural .cdx and a
    Memo field.
    29 	Code page mark
    30 ? 31 	Reserved, contains 0x00
    32 ? n 	Field subrecords
    The number of fields determines the number of field subrecords.
    One field subrecord exists for each field in the table.
    n+1 			Header record terminator (0x0D)
    n+2 to n+264 	A 263-byte range that contains the backlink, which is the
    relative path of an associated database (.dbc) file, information.
    If the first byte is 0x00, the file is not associated with a database.
    Therefore, database files always contain 0x00.
    see also ftp://fship.com/pub/multisoft/flagship/docu/dbfspecs.txt
    
    */

METHOD Read(hFile as IntPtr) AS LOGIC
    VAR nPos := FTell(hFile)
    FSeek3(hFile, 0, FS_SET)
    VAR Ok := FRead3(hFile, SELF:Buffer, DbfHeader.SIZE) == DbfHeader.SIZE
    IF Ok
        FSeek3(hFile, (LONG) nPos, FS_SET)
    ENDIF
    RETURN Ok

METHOD Write(hFile as IntPtr) AS LOGIC
	LOCAL dtInfo AS DateTime
	dtInfo := DateTime.Now
    // Update the Date/Time information
	SELF:Year   := (BYTE)(dtInfo:Year % 100)
	SELF:Month  := (BYTE)dtInfo:Month
	SELF:Day    := (BYTE)dtInfo:Day

    VAR nPos := FTell(hFile)
    FSeek3(hFile, 0, FS_SET)
    VAR Ok := FWrite3(hFile, SELF:Buffer, DbfHeader.SIZE) == DbfHeader.SIZE
    IF Ok
        FSeek3(hFile, (LONG) nPos, FS_SET)
        SELF:isHot := FALSE
    ENDIF
    RETURN Ok


END CLASS



END CLASS
// Inspired by Harbour
/// <summary>This structure holds the various settings for locking models</summary>
STRUCTURE DbfLocking
    /// <summary>Offset of the Locking </summary>
	PUBLIC Offset AS INT64
    /// <summary>Length for File locks </summary>
	PUBLIC FileSize AS INT64
    /// <summary>Length for Record locks </summary>
	PUBLIC RecordSize AS LONG
    /// <summary>Direction of locking, used to calculate file lock offsets and record lock offsets</summary>
	PUBLIC Direction AS LONG

/// <summary>Set various numbers based on a locking model.</summary>	
METHOD Initialize( model AS DbfLockingModel ) AS VOID
	SWITCH model
	CASE DbfLockingModel.Clipper52
		SELF:Offset     := 1000000000
		SELF:FileSize   := 1000000000
		SELF:RecordSize := 1
		SELF:Direction  := 1
	CASE DbfLockingModel.Clipper53
		SELF:Offset     := 1000000000
		SELF:FileSize   := 1000000000
		SELF:RecordSize := 1
		SELF:Direction  := 1
	CASE DbfLockingModel.Clipper53Ext
		SELF:Offset     := 4000000000
		SELF:FileSize   := 294967295
		SELF:RecordSize := 1
		SELF:Direction  := 1
	CASE DbfLockingModel.FoxPro
		SELF:Offset     := 0x40000000
		SELF:FileSize   := 0x07ffffff
		SELF:RecordSize := 1
		SELF:Direction  := 2
	CASE DbfLockingModel.FoxProExt
		SELF:Offset     := 0x7ffffffe
		SELF:FileSize   := 0x3ffffffd
		SELF:RecordSize := 1
		SELF:Direction  := -1
	CASE DbfLockingModel.Harbour64
		SELF:Offset     := 0x7FFFFFFF00000001
		SELF:FileSize   := 0x7ffffffe
		SELF:RecordSize := 1
		SELF:Direction  := 1
	CASE DbfLockingModel.VoAnsi
		SELF:Offset     := 0x80000000
		SELF:FileSize   := 0x7fffffff
		SELF:RecordSize := 1
		SELF:Direction  := 1
	END SWITCH
    /// <summary>File Lock offsets </summary>
    PROPERTY FileLockOffSet AS INT64
        GET
            VAR iOffset := SELF:Offset
	        IF SELF:Direction < 0 
		        iOffset -= SELF:FileSize
	        ELSE
		        iOffset++
            ENDIF
            RETURN iOffset
        END GET
    END PROPERTY
    /// <summary>Calculate the record offset based </summary>
    METHOD RecnoOffSet(recordNbr AS LONG, recSize AS LONG, headerLength AS LONG) AS INT64
	    VAR iOffset := SELF:Offset
	    IF SELF:Direction < 0 
		    iOffset -= (INT64)recordNbr
	    ELSEIF( SELF:Direction == 2 )
		    iOffset += (INT64)( ( recordNbr - 1 ) * recSize + headerLength )
	    ELSE
		    iOffset += (INT64) recordNbr
	    ENDIF
        RETURN iOffset
END STRUCTURE




INTERNAL CLASS DBFSortCompare IMPLEMENTS IComparer<SortRecord>
	
	PRIVATE _sortInfo AS DbSortInfo
	PRIVATE _dataX AS BYTE[]
	PRIVATE _dataY AS BYTE[]
	
INTERNAL CONSTRUCTOR( rdd AS DBF, info AS DbSortInfo )
	SELF:_sortInfo  := info
	LOCAL max       := 0 AS INT
	FOREACH VAR item IN info:Items
		max := Math.Max(max, item:Length)
	NEXT
	SELF:_dataX := BYTE[]{ max}     
	SELF:_dataY := BYTE[]{ max}
	
	
PUBLIC METHOD Compare(recordX AS SortRecord , recordY AS SortRecord ) AS LONG
	LOCAL dataBufferX AS BYTE[]
	LOCAL dataBufferY AS BYTE[]
	LOCAL diff AS LONG
	IF recordX:Recno == recordY:Recno
		RETURN 0
	ENDIF
    //
	dataBufferX := recordX:Data
	dataBufferY := recordY:Data
	diff := 0
	FOREACH VAR item IN SELF:_sortInfo:Items
		VAR start := item:OffSet
		VAR iLen := item:Length
		VAR flags := item:Flags
        // Long Value ?
		IF flags:HasFlag(DbSortFlags.Long)
			VAR longValue1 := BitConverter.ToInt32(dataBufferX, start)
			VAR longValue2 := BitConverter.ToInt32(dataBufferY, start)
			diff := longValue1 - longValue2
		ELSE
            // String Value ?
			IF flags:HasFlag(DbSortFlags.Ascii)
                // String ASCII : Use Runtime comparer
				Array.Copy(dataBufferX, start, _dataX, 0, iLen)
				Array.Copy(dataBufferY, start, _dataY, 0, iLen)
				diff := XSharp.RuntimeState.StringCompare(_dataX, _dataY, iLen)
                //
			ELSE
				FOR VAR i := 0 TO iLen
					diff := dataBufferX[i + start] - dataBufferY[i + start]
					IF diff != 0
						EXIT
					ENDIF
				NEXT
			ENDIF
		ENDIF
		IF diff != 0
			IF flags:HasFlag(DbSortFlags.Descending)
				diff *= -1
			ENDIF
			EXIT
		ENDIF
	NEXT
	IF diff == 0
		diff := recordX:Recno - recordY:Recno
	ENDIF
RETURN diff




END CLASS

    /// <summary>DBF Field.</summary>
STRUCTURE DbfField
	PRIVATE CONST OFFSET_NAME		   := 0    AS BYTE
	PRIVATE CONST OFFSET_TYPE		   := 11   AS BYTE
	PRIVATE CONST OFFSET_OFFSET	       := 12   AS BYTE
	PRIVATE CONST OFFSET_LEN          := 16   AS BYTE
	PRIVATE CONST OFFSET_DEC          := 17   AS BYTE
	PRIVATE CONST OFFSET_FLAGS        := 18   AS BYTE
	PRIVATE CONST OFFSET_COUNTER      := 19   AS BYTE
	PRIVATE CONST OFFSET_INCSTEP      := 23   AS BYTE
	PRIVATE CONST OFFSET_RESERVED1    := 24   AS BYTE
	PRIVATE CONST OFFSET_RESERVED2    := 25   AS BYTE
	PRIVATE CONST OFFSET_RESERVED3    := 26   AS BYTE
	PRIVATE CONST OFFSET_RESERVED4    := 27   AS BYTE
	PRIVATE CONST OFFSET_RESERVED5    := 28   AS BYTE
	PRIVATE CONST OFFSET_RESERVED6	   := 29  AS BYTE
	PRIVATE CONST OFFSET_RESERVED7    := 30   AS BYTE
	PRIVATE CONST OFFSET_HASTAG       := 31   AS BYTE
	INTERNAL CONST NAME_SIZE           := 11  AS BYTE
	INTERNAL CONST SIZE                := 32  AS BYTE
	INTERNAL Encoding as System.Text.Encoding
    // Fixed Buffer of 32 bytes
    // Matches the DBF layout
    // Read/Write to/from the Stream with the Buffer
    // and access individual values using the other fields
METHOD initialize() AS VOID
	SELF:Buffer := BYTE[]{SIZE}
	
	PUBLIC Buffer		 AS BYTE[]

METHOD ClearFlags() AS VOID
    System.Array.Clear(Buffer, OFFSET_FLAGS, SIZE-OFFSET_FLAGS)
    RETURN
	
PROPERTY Name		 AS STRING
	GET
		LOCAL fieldName := BYTE[]{DbfField.NAME_SIZE} AS BYTE[]
		Array.Copy( Buffer, OFFSET_NAME, fieldName, 0, DbfField.NAME_SIZE )
		LOCAL count := Array.FindIndex<BYTE>( fieldName, 0, { sz => sz == 0 } ) AS INT
		IF count == -1
			count := DbfField.NAME_SIZE
		ENDIF
		LOCAL str := Encoding:GetString( fieldName,0, count ) AS STRING
		IF str == NULL 
			str := String.Empty
		ENDIF
		str := str:Trim()
		RETURN str
	END GET
	SET
            // Be sure to fill the Buffer with 0
		Array.Clear( Buffer, OFFSET_NAME, DbfField.NAME_SIZE )
		Encoding:GetBytes( value, 0, Math.Min(DbfField.NAME_SIZE,value:Length), Buffer, OFFSET_NAME )
	END SET
END PROPERTY

PROPERTY Type		 AS DbFieldType ;
        GET (DbFieldType) Buffer[ OFFSET_TYPE ] ;
        SET Buffer[ OFFSET_TYPE ] := (BYTE) value
	
    // Offset from record begin in FP
PROPERTY Offset 	 AS LONG ;
        GET BitConverter.ToInt32(Buffer, OFFSET_OFFSET);
        SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_OFFSET, SIZEOF(LONG))
	
PROPERTY Len		 AS BYTE;
        GET Buffer[OFFSET_LEN]  ;
        SET Buffer[OFFSET_LEN] := value
	
PROPERTY Dec		 AS BYTE;
        GET Buffer[OFFSET_DEC]  ;
        SET Buffer[OFFSET_DEC] := value
	
PROPERTY Flags		 AS DBFFieldFlags;
        GET (DBFFieldFlags)Buffer[OFFSET_FLAGS] ;
        SET Buffer[OFFSET_FLAGS] := (BYTE) value
	
PROPERTY Counter	 AS LONG;
        GET BitConverter.ToInt32(Buffer, OFFSET_COUNTER);
        SET Array.Copy(BitConverter.GetBytes(value),0, Buffer, OFFSET_COUNTER, SIZEOF(LONG))
	
PROPERTY IncStep	 AS BYTE;
        GET Buffer[OFFSET_INCSTEP]  ;
        SET Buffer[OFFSET_INCSTEP] :=  value
	
PROPERTY Reserved1   AS BYTE;
        GET Buffer[OFFSET_RESERVED1]  ;
        SET Buffer[OFFSET_RESERVED1] :=  value
	
PROPERTY Reserved2   AS BYTE;
        GET Buffer[OFFSET_RESERVED2]  ;
        SET Buffer[OFFSET_RESERVED2] := value
	
PROPERTY Reserved3   AS BYTE;
        GET Buffer[OFFSET_RESERVED3]  ;
        SET Buffer[OFFSET_RESERVED3] :=  value
	
PROPERTY Reserved4  AS BYTE;
        GET Buffer[OFFSET_RESERVED4]  ;
        SET Buffer[OFFSET_RESERVED4] :=  value
	
PROPERTY Reserved5   AS BYTE;
        GET Buffer[OFFSET_RESERVED5]  ;
        SET Buffer[OFFSET_RESERVED5] :=  value
	
PROPERTY Reserved6   AS BYTE;
        GET Buffer[OFFSET_RESERVED6]  ;
        SET Buffer[OFFSET_RESERVED6] :=  value
	
PROPERTY Reserved7   AS BYTE;
        GET Buffer[OFFSET_RESERVED7]  ;
        SET Buffer[OFFSET_RESERVED7] :=  value
	
PROPERTY HasTag		 AS BYTE;
        GET Buffer[OFFSET_HASTAG]  ;
        SET Buffer[OFFSET_HASTAG] :=  value
END STRUCTURE



/*
    /// <summary>DBase 7 Field.</summary>
[StructLayout(LayoutKind.Explicit)];
STRUCTURE Dbf7Field
// Dbase 7 has 32 Bytes for Field Names
// Fixed Buffer of 32 bytes
// Matches the DBF layout
// Read/Write to/from the Stream with the Buffer
// and access individual values using the other fields
	[FieldOffset(00)] PUBLIC Buffer		 AS BYTE[]
	[FieldOffset(00)] PUBLIC Name		 AS BYTE[]    // Field name in ASCII (zero-filled).
	[FieldOffset(32)] PUBLIC Type		 AS BYTE 	// Field type in ASCII (B, C, D, N, L, M, @, I, +, F, 0 or G).
	[FieldOffset(33)] PUBLIC Len		 AS BYTE 	// Field length in binary.
	[FieldOffset(34)] PUBLIC Dec		 AS BYTE
	[FieldOffset(35)] PUBLIC Reserved1	 AS SHORT
	[FieldOffset(37)] PUBLIC HasTag		 AS BYTE    // Production .MDX field flag; 0x01 if field has an index tag in the production .MDX file; 0x00 if the field is not indexed.
	[FieldOffset(38)] PUBLIC Reserved2	 AS SHORT
	[FieldOffset(40)] PUBLIC Counter	 AS LONG	// Next Autoincrement value, if the Field type is Autoincrement, 0x00 otherwise.
	[FieldOffset(44)] PUBLIC Reserved3	 AS LONG
	
END STRUCTURE
*/
END NAMESPACE



