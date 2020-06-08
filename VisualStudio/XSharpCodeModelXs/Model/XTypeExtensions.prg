//
// Copyright (c) XSharp B.V.  All Rights Reserved.  
// Licensed under the Apache License, Version 2.0.  
// See License.txt in the project root for license information.
//

USING System
USING System.Collections.Generic
USING System.Linq
 
BEGIN NAMESPACE XSharpModel
	
	STATIC CLASS XTypeExtensions
    STATIC METHOD GetDescription(SELF type as IXType) AS STRING
     	VAR modVis := type:ModVis
      IF  type:IsStatic
         modVis += "STATIC "
      ENDIF
      RETURN modVis + type:Kind:ToString() + " " + type:Prototype
   
   STATIC METHOD GetFullName(SELF type as IXType) AS STRING
      IF ! String.IsNullOrEmpty(type:Namespace)
         var result := type:Namespace + "." + type:Name
         return result            
      ENDIF
      RETURN type:Name
   
   STATIC METHOD GetMethods(SELF type as IXType) AS IXMember[]
      return type:Members:Where( { m => m.Kind == Kind.Method }):ToArray()

   STATIC METHOD GetFields(SELF type as IXType) AS IXMember[]
      return type:Members:Where( { m => m.Kind:IsField()}):ToArray()

   STATIC METHOD GetEvents(SELF type as IXType) AS IXMember[]
      return type:Members:Where( { m => m.Kind == Kind.Event}):ToArray()

   STATIC METHOD GetProperties(SELF type as IXType) AS IXMember[]
      return type:Members:Where( { m => m.Kind:IsProperty()}):ToArray()

   STATIC METHOD GetMember(SELF type as IXType, strName as STRING) AS IXMember[]
      return type:Members:Where( { m => m.Name == strName}):ToArray()

   STATIC METHOD GetMethod(SELF type as IXType, strName as STRING) AS IXMember[]
      return type:Members:Where( { m => m.Name == strName .and. m.Kind == Kind.Method}):ToArray()

   STATIC METHOD GetProperty(SELF type as IXType, strName as STRING) AS IXMember[]
      return type:Members:Where( { m => m.Name == strName .and. m.Kind:IsProperty()}):ToArray()

   STATIC METHOD GetField(SELF type as IXType, strName as STRING) AS IXMember[]
      return type:Members:Where( { m => m.Name == strName .and. m.Kind:IsField() }):ToArray()

   STATIC METHOD GetXmlSignature(SELF tm as IXType) AS STRING
         RETURN "T:"+tm:FullName

   STATIC METHOD MatchesTypeName(SELF tm as IXType, nameToMatch as STRING) AS LOGIC
      IF tm:FullName == nameToMatch
         return true
      ENDIF
      FOREACH var ifName in tm:Interfaces
         IF ifName == nameToMatch
            return true
         ENDIF
      NEXT      
      RETURN FALSE

	END CLASS
END NAMESPACE 


