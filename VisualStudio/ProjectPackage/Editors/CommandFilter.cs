﻿//
// Copyright (c) XSharp B.V.  All Rights Reserved.
// Licensed under the Apache License, Version 2.0.
// See License.txt in the project root for license information.
//
using System;
using System.ComponentModel.Composition;
using System.Diagnostics;
using Microsoft.VisualStudio.OLE.Interop;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.TextManager.Interop;
using Microsoft.VisualStudio.Utilities;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Package;
using System.Runtime.InteropServices;
using Microsoft.VisualStudio.Editor;
using Microsoft.VisualStudio.Language.Intellisense;
using LanguageService.SyntaxTree;
using LanguageService.CodeAnalysis.XSharp.SyntaxParser;
using System.Collections.Generic;
using System.Reflection;
using Microsoft.VisualStudio.Text.Operations;
using Microsoft.VisualStudio.Text.Classification;
using Microsoft.VisualStudio.Text.Tagging;
using Microsoft.VisualStudio.Text.Editor.OptionsExtensionMethods;
using XSharpColorizer;
namespace XSharp.Project
{
    internal sealed class CommandFilter : IOleCommandTarget
    {
        ICompletionSession _completionSession;
        public IWpfTextView TextView { get; private set; }
        public ICompletionBroker CompletionBroker { get; private set; }
        public IOleCommandTarget Next { get; set; }



        ISignatureHelpBroker SignatureBroker;
        ISignatureHelpSession _signatureSession;
        ITextStructureNavigator m_navigator;
        IBufferTagAggregatorFactoryService Aggregator;


        public CommandFilter(IWpfTextView textView, ICompletionBroker completionBroker, ITextStructureNavigator nav, ISignatureHelpBroker signatureBroker, IBufferTagAggregatorFactoryService aggregator)
        {
            m_navigator = nav;

            _completionSession = null;
            _signatureSession = null;

            TextView = textView;
            CompletionBroker = completionBroker;
            SignatureBroker = signatureBroker;
            Aggregator = aggregator;
        }

        private char GetTypeChar(IntPtr pvaIn)
        {
            return (char)(ushort)Marshal.GetObjectForNativeVariant(pvaIn);
        }

        public int Exec(ref Guid pguidCmdGroup, uint nCmdID, uint nCmdexecopt, IntPtr pvaIn, IntPtr pvaOut)
        {
            bool handled = false;
            bool completeAndStart = false;
            int hresult = VSConstants.S_OK;

            // 1. Pre-process
            if (pguidCmdGroup == VSConstants.VSStd2K)
            {
                switch ((VSConstants.VSStd2KCmdID)nCmdID)
                {
                    case VSConstants.VSStd2KCmdID.FORMATDOCUMENT:
                        FormatDocument();
                        break;
                    case VSConstants.VSStd2KCmdID.AUTOCOMPLETE:
                    case VSConstants.VSStd2KCmdID.COMPLETEWORD:
                    case VSConstants.VSStd2KCmdID.SHOWMEMBERLIST:
                        CancelSignatureSession();
                        handled = StartCompletionSession(nCmdID, '\0');
                        break;
                    case VSConstants.VSStd2KCmdID.RETURN:
                        handled = CompleteCompletionSession(false);
                        break;

                    case VSConstants.VSStd2KCmdID.TAB:
                        handled = CompleteCompletionSession(true);
                        break;
                    case VSConstants.VSStd2KCmdID.CANCEL:
                        handled = CancelCompletionSession();
                        break;
                    case VSConstants.VSStd2KCmdID.PARAMINFO:
                        StartSignatureSession(false);
                        break;
                    case VSConstants.VSStd2KCmdID.BACKSPACE:
                        if (_signatureSession != null)
                        {
                            int pos = TextView.Caret.Position.BufferPosition ;
                            if (pos > 0)
                            {
                                // get previous char
                                var previous = TextView.TextBuffer.CurrentSnapshot.GetText().Substring(pos - 1, 1);
                                if (previous == "(" || previous == "{")
                                {
                                    _signatureSession.Dismiss();
                                }
                            }

                        }
                        break;
                    case VSConstants.VSStd2KCmdID.TYPECHAR:
                        char ch = GetTypeChar(pvaIn);
                        if (_completionSession != null)
                        {
                            if (Char.IsLetterOrDigit(ch) || ch == '_')
                                Filter();
                            else
                                CancelCompletionSession();
                        }
                        // Comma starts signature session
                        if (ch == ',')
                        {
                            StartSignatureSession(true);
                        }
                        break;
                }
            }
            else if (pguidCmdGroup == VSConstants.GUID_VSStandardCommandSet97)
            {
                switch ((VSConstants.VSStd97CmdID)nCmdID)
                {
                    case VSConstants.VSStd97CmdID.GotoDefn:
                        GotoDefn();
                        return VSConstants.S_OK;
                }
            }


            if (!handled)
                hresult = Next.Exec(pguidCmdGroup, nCmdID, nCmdexecopt, pvaIn, pvaOut);

            if (ErrorHandler.Succeeded(hresult))
            {
                if (pguidCmdGroup == Microsoft.VisualStudio.VSConstants.VSStd2K)
                {
                    switch ((VSConstants.VSStd2KCmdID)nCmdID)
                    {
                        case VSConstants.VSStd2KCmdID.TYPECHAR:
                            char ch = GetTypeChar(pvaIn);
                            if (_completionSession != null)
                            {
                                if (completeAndStart)
                                {
                                    StartCompletionSession(nCmdID, ch);
                                }
                            }
                            else
                            {
                                switch (ch)
                                {
                                    case ':':
                                    case '.':
                                        CancelSignatureSession();
                                        StartCompletionSession(nCmdID, ch);
                                        break;
                                    case '(':
                                    case '{':
                                        StartSignatureSession(false);
                                        break;
                                    case ')':
                                    case '}':
                                        if (_signatureSession != null)
                                        {
                                            _signatureSession.Dismiss();
                                            _signatureSession = null;
                                        }
                                        break;
                                    default:
                                        //if (_signatureSession != null)
                                        //{
                                        //    SnapshotPoint current = this.TextView.Caret.Position.BufferPosition;
                                        //    int line = current.GetContainingLine().LineNumber;
                                        //    int pos = current.Position;
                                        //    //
                                        //    int startLine = (int)_signatureSession.Properties["Line"];
                                        //    int startPos = (int)_signatureSession.Properties["Start"];
                                        //    if ( !(( line == startLine ) && ( pos >= startPos )) )
                                        //    {
                                        //        CancelSignatureSession();
                                        //    }
                                        //}
                                        break;
                                }
                            }
                            break;
                        case VSConstants.VSStd2KCmdID.BACKSPACE:
                            Filter();
                            break;
                        case VSConstants.VSStd2KCmdID.COMPLETEWORD:

                            break;
                    }
                }
            }

            return hresult;
        }

        private void FormatDocument()
        {
            var buffer = this.TextView.TextBuffer;
            //
            var tagAggregator = Aggregator.CreateTagAggregator<IClassificationTag>(buffer);
            SnapshotSpan docSpan = new SnapshotSpan(buffer.CurrentSnapshot, 0, buffer.CurrentSnapshot.Length);
            var tags = tagAggregator.GetTags(docSpan);
            //
            Stack<Span> regionStarts = new Stack<Microsoft.VisualStudio.Text.Span>();
            List<Tuple<Span, Span>> regions = new List<Tuple<Microsoft.VisualStudio.Text.Span, Microsoft.VisualStudio.Text.Span>>();
            //
            foreach (var tag in tags)
            {
                var name = tag.Tag.ClassificationType.Classification.ToLower();
                //
                if (name.Contains(XSharpColorizer.ColorizerConstants.XSharpRegionStartFormat))
                {
                    if (System.Diagnostics.Debugger.IsAttached)
                        System.Diagnostics.Debugger.Break();
                    //
                    var spans = tag.Span.GetSpans(this.TextView.TextSnapshot);
                    if (spans.Count > 0)
                        regionStarts.Push(spans[0]);
                }
                else if (name.Contains(XSharpColorizer.ColorizerConstants.XSharpRegionStopFormat))
                {
                    var spans = tag.Span.GetSpans(this.TextView.TextSnapshot);
                    if (spans.Count > 0)
                    {
                        if (regionStarts.Count > 0)
                        {
                            var start = regionStarts.Pop();
                            //
                            regions.Add(new Tuple<Span, Span>(start, spans[0]));
                        }
                    }
                }
            }
            //Now, we have a list of Regions Start/Stop
            var editor = buffer.CreateEdit();
            //
            int tabSize = this.TextView.Options.GetTabSize();
            //
            //foreach( var region in regions )
            //{
            //    SnapshotPoint pt = new SnapshotPoint(this.TextView.TextSnapshot, region.Item1.Start);
            //    var snapLine = pt.GetContainingLine();
            //    snapLine.
            //}
            //var lines = this.TextView.TextViewLines;
            //foreach( var twLine in lines )
            //{
            //    var fullSpan = new SnapshotSpan(twLine.Snapshot, Span.FromBounds(twLine.Start, twLine.End));
            //    var snapLine = fullSpan.Start.GetContainingLine();
            //    int lineNumber = fullSpan.Start.GetContainingLine().LineNumber + 1;
            //    string text = snapLine.GetText();
            //    //
            //    lines.
            //    //
            //}

        }

        private void GotoDefn()
        {
            // First, where are we ?
            int caretPos = this.TextView.Caret.Position.BufferPosition.Position;
            int lineNumber = this.TextView.Caret.Position.BufferPosition.GetContainingLine().LineNumber;
            String currentText = this.TextView.TextBuffer.CurrentSnapshot.GetText();
            XSharpModel.XFile file= this.TextView.TextBuffer.GetFile();
            if (file == null)
                return;
            // Then, the corresponding Type/Element if possible
            IToken stopToken;
            //ITokenStream tokenStream;
            List<String> tokenList = XSharpLanguage.XSharpTokenTools.GetTokenList(caretPos, lineNumber, currentText, out stopToken, true, file);
            // Check if we can get the member where we are
            XSharpModel.XTypeMember member = XSharpLanguage.XSharpTokenTools.FindMember(caretPos, file);
            XSharpModel.XType currentNamespace = XSharpLanguage.XSharpTokenTools.FindNamespace(caretPos, file);
            // LookUp for the BaseType, reading the TokenList (From left to right)
            XSharpLanguage.CompletionElement gotoElement;
            String currentNS = "";
            if (currentNamespace != null)
            {
                currentNS = currentNamespace.Name;
            }
            XSharpModel.CompletionType cType = XSharpLanguage.XSharpTokenTools.RetrieveType(file, tokenList, member, currentNS, stopToken, out gotoElement);
            //
            if ((gotoElement != null) && (gotoElement.XSharpElement != null))
            {
                // Ok, find it ! Let's go ;)
                gotoElement.XSharpElement.OpenEditor();
            }
            //
        }


        #region Completion Session
        private void Filter()
        {
            if (_completionSession == null)
                return;
            _completionSession.SelectedCompletionSet.Filter();
            _completionSession.SelectedCompletionSet.SelectBestMatch();
            //_currentSession.SelectedCompletionSet.Recalculate();
        }

        bool CancelCompletionSession()
        {
            if (_completionSession == null)
                return false;

            _completionSession.Dismiss();

            return true;
        }

        bool CompleteCompletionSession(bool force)
        {
            if (_completionSession == null)
                return false;

            if (!_completionSession.SelectedCompletionSet.SelectionStatus.IsSelected && !force)
            {
                _completionSession.Dismiss();
                return false;
            }
            else
            {
                //
                _completionSession.Commit();
                return true;
            }
        }

        bool StartCompletionSession(uint nCmdId, char typedChar)
        {
            if (_completionSession != null)
                return false;

            SnapshotPoint caret = TextView.Caret.Position.BufferPosition;
            ITextSnapshot snapshot = caret.Snapshot;

            if (!CompletionBroker.IsCompletionActive(TextView))
            {
                _completionSession = CompletionBroker.CreateCompletionSession(TextView, snapshot.CreateTrackingPoint(caret, PointTrackingMode.Positive), true);
            }
            else
            {
                _completionSession = CompletionBroker.GetSessions(TextView)[0];
            }

            _completionSession.Dismissed += OnCompletionSessionDismiss;
            _completionSession.Committed += OnCompletionSessionCommitted;

            _completionSession.Properties["Command"] = nCmdId;
            _completionSession.Properties["Char"] = typedChar;
            _completionSession.Properties["Type"] = null;
            try
            {
                _completionSession.Start();
            }
            catch (Exception e)
            {
                Support.Debug("Startcompletion failed:" + e.Message);
            }
            return true;
        }

        private void OnCompletionSessionCommitted(object sender, EventArgs e)
        {
            // it MUST be the case....
            if (_completionSession.SelectedCompletionSet.SelectionStatus.Completion != null)
            {
                if (_completionSession.SelectedCompletionSet.SelectionStatus.Completion.InsertionText.EndsWith("("))
                {
                    XSharpModel.CompletionType cType = null;
                    if (_completionSession.Properties["Type"] != null)
                    {
                        cType = (XSharpModel.CompletionType)_completionSession.Properties["Type"];
                    }
                    string method = _completionSession.SelectedCompletionSet.SelectionStatus.Completion.InsertionText;
                    method = method.Substring(0, method.Length - 1);
                    StartSignatureSession(false, cType, method);
                }
            }
            //
        }

        private void OnCompletionSessionDismiss(object sender, EventArgs e)
        {
            _completionSession = null;
        }
        #endregion


        #region Signature Session
        bool StartSignatureSession(bool comma, XSharpModel.CompletionType cType = null, string methodName = null)
        {
            if (_signatureSession != null)
                return false;
            int startLineNumber = this.TextView.Caret.Position.BufferPosition.GetContainingLine().LineNumber;
            SnapshotPoint ssp = this.TextView.Caret.Position.BufferPosition;
            // when coming from the completionlist then there is no need to check a lot of stuff
            // we can then simply lookup the method and that is it.
            // Also no need to filter on visibility since that has been done in the completionlist already !
            XSharpLanguage.CompletionElement gotoElement = null;
            if (cType != null && methodName != null)
            {
                cType = XSharpLanguage.XSharpTokenTools.SearchMethodTypeIn(cType, methodName, XSharpModel.Modifiers.Private, false, out gotoElement);

            }
            else
            {
                // First, where are we ?
                int caretPos;
                int lineNumber = startLineNumber;
                //
                do
                {
                    if (ssp.Position == 0)
                        break;
                    ssp = ssp - 1;
                    char leftCh = ssp.GetChar();
                    if ((leftCh == '(') || (leftCh == '{'))
                        break;
                    lineNumber = ssp.GetContainingLine().LineNumber;
                } while (startLineNumber == lineNumber);
                //
                caretPos = ssp.Position;
                String currentText = this.TextView.TextBuffer.CurrentSnapshot.GetText();
                XSharpModel.XFile file = this.TextView.TextBuffer.GetFile();
                if (file == null)
                    return false;
                // Then, the corresponding Type/Element if possible
                IToken stopToken;
                //ITokenStream tokenStream;
                List<String> tokenList = XSharpLanguage.XSharpTokenTools.GetTokenList(caretPos, lineNumber, currentText, out stopToken, true, file);
                // Check if we can get the member where we are
                XSharpModel.XTypeMember member = XSharpLanguage.XSharpTokenTools.FindMember(caretPos, file);
                XSharpModel.XType currentNamespace = XSharpLanguage.XSharpTokenTools.FindNamespace(caretPos, file);
                // LookUp for the BaseType, reading the TokenList (From left to right)
                String currentNS = "";
                if (currentNamespace != null)
                {
                    currentNS = currentNamespace.Name;
                }
                cType = XSharpLanguage.XSharpTokenTools.RetrieveType(file, tokenList, member, currentNS, stopToken, out gotoElement);
            }
            //
            if ((gotoElement != null) && (gotoElement.IsInitialized))
            {
                // Not sure that this if() is still necessary ...
                if ((gotoElement.XSharpElement != null) && (gotoElement.XSharpElement.Kind == XSharpModel.Kind.Class))
                {
                    XSharpModel.XType xType = gotoElement.XSharpElement as XSharpModel.XType;
                    if (xType != null)
                    {
                        foreach (XSharpModel.XTypeMember mbr in xType.Members)
                        {
                            if (String.Compare(mbr.Name, "constructor", true) == 0)
                            {
                                gotoElement = new XSharpLanguage.CompletionElement(mbr);
                                break;
                            }
                        }
                    }
                }

                SnapshotPoint caret = TextView.Caret.Position.BufferPosition;
                ITextSnapshot snapshot = caret.Snapshot;
                //
                if (!SignatureBroker.IsSignatureHelpActive(TextView))
                {
                    _signatureSession = SignatureBroker.CreateSignatureHelpSession(TextView, snapshot.CreateTrackingPoint(caret, PointTrackingMode.Positive), true);
                }
                else
                {
                    _signatureSession = SignatureBroker.GetSessions(TextView)[0];
                }

                _signatureSession.Dismissed += OnSignatureSessionDismiss;
                if (gotoElement.XSharpElement != null)
                {
                    _signatureSession.Properties["Element"] = gotoElement.XSharpElement;
                }
                else if (gotoElement.SystemElement != null)
                {
                    _signatureSession.Properties["Element"] = gotoElement.SystemElement;
                }
                else if (gotoElement.CodeElement != null)
                {
                    _signatureSession.Properties["Element"] = gotoElement.CodeElement;
                }
                _signatureSession.Properties["Line"] = startLineNumber;
                _signatureSession.Properties["Start"] = ssp.Position;
                _signatureSession.Properties["Length"] = TextView.Caret.Position.BufferPosition.Position - ssp.Position;
                _signatureSession.Properties["Comma"] = comma;

                try
                {
                    _signatureSession.Start();
                }
                catch (Exception e)
                {
                    Support.Debug("Start Signature session failed:" + e.Message);
                }
            }
            //
            return true;
        }

        bool CancelSignatureSession()
        {
            if (_signatureSession == null)
                return false;

            _signatureSession.Dismiss();
            return true;
        }

        private void OnSignatureSessionDismiss(object sender, EventArgs e)
        {
            _signatureSession = null;
        }
        #endregion

        public int QueryStatus(ref Guid pguidCmdGroup, uint cCmds, OLECMD[] prgCmds, IntPtr pCmdText)
        {
            if (pguidCmdGroup == VSConstants.VSStd2K)
            {
                switch ((VSConstants.VSStd2KCmdID)prgCmds[0].cmdID)
                {
                    case VSConstants.VSStd2KCmdID.AUTOCOMPLETE:
                    case VSConstants.VSStd2KCmdID.COMPLETEWORD:
                        prgCmds[0].cmdf = (uint)OLECMDF.OLECMDF_ENABLED | (uint)OLECMDF.OLECMDF_SUPPORTED;
                        return VSConstants.S_OK;
                }
            }
            else if (pguidCmdGroup == VSConstants.GUID_VSStandardCommandSet97)
            {
                switch ((VSConstants.VSStd97CmdID)prgCmds[0].cmdID)
                {
                    case VSConstants.VSStd97CmdID.GotoDefn:
                        prgCmds[0].cmdf = (uint)OLECMDF.OLECMDF_ENABLED | (uint)OLECMDF.OLECMDF_SUPPORTED;
                        return VSConstants.S_OK;
                }
            }
            return Next.QueryStatus(pguidCmdGroup, cCmds, prgCmds, pCmdText);
        }




    }


}
