﻿//
// Copyright (c) XSharp B.V.  All Rights Reserved.  
// Licensed under the Apache License, Version 2.0.  
// See License.txt in the project root for license information.
//
using LanguageService.CodeAnalysis;
using LanguageService.CodeAnalysis.XSharp;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.TableManager;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XSharpModel
{
    public interface IXSharpProject
    {

        string RootNameSpace { get; }
        string Url { get; }
        void SetStatusBarText(string message);
        void OpenElement(string file, int line, int column);

        void ClearIntellisenseErrors(string file);
        void AddIntellisenseError(string file, int line, int column, int Length, string errCode, string message, DiagnosticSeverity sev);
        void ShowIntellisenseErrors();
        bool IsDocumentOpen(string file);
        List<IXErrorPosition> GetIntellisenseErrorPos(string fileName);
        XSharpParseOptions ParseOptions { get; }
    }

    public interface IXErrorPosition
    {
        int Line { get; }
        int Column { get; }
        int Length { get; }
    }

}
