﻿//
// Copyright (c) XSharp B.V.  All Rights Reserved.  
// Licensed under the Apache License, Version 2.0.  
// See License.txt in the project root for license information.
//
namespace XSharp.Project
{
	partial class XSharpSLEPropertyForm
	{
		/// <summary>
		/// Required designer variable.
		/// </summary>
		private System.ComponentModel.IContainer components = null;

		/// <summary>
		/// Clean up any resources being used.
		/// </summary>
		/// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
		protected override void Dispose(bool disposing)
		{
			if (disposing && (components != null))
			{
				components.Dispose();
			}
			base.Dispose(disposing);
		}

		#region Windows Form Designer generated code

		/// <summary>
		/// Required method for Designer support - do not modify
		/// the contents of this method with the code editor.
		/// </summary>
		private void InitializeComponent()
		{
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(XSharpSLEPropertyForm));
            this.tableLayoutPanel1 = new System.Windows.Forms.TableLayoutPanel();
            this.PropertyText = new System.Windows.Forms.TextBox();
            this.MacrosList = new System.Windows.Forms.ListView();
            this.MacroColumn = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.ValueColumn = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.flowLayoutPanel1 = new System.Windows.Forms.FlowLayoutPanel();
            this.InsertFilenameBtn = new System.Windows.Forms.Button();
            this.InsertPathBtn = new System.Windows.Forms.Button();
            this.InsertMacroButton = new System.Windows.Forms.Button();
            this.OKButton = new System.Windows.Forms.Button();
            this.CancelBtn = new System.Windows.Forms.Button();
            this.tableLayoutPanel1.SuspendLayout();
            this.flowLayoutPanel1.SuspendLayout();
            this.SuspendLayout();
            // 
            // tableLayoutPanel1
            // 
            this.tableLayoutPanel1.ColumnCount = 1;
            this.tableLayoutPanel1.ColumnStyles.Add(new System.Windows.Forms.ColumnStyle(System.Windows.Forms.SizeType.Percent, 100F));
            this.tableLayoutPanel1.Controls.Add(this.PropertyText, 0, 0);
            this.tableLayoutPanel1.Controls.Add(this.MacrosList, 0, 1);
            this.tableLayoutPanel1.Controls.Add(this.flowLayoutPanel1, 0, 2);
            this.tableLayoutPanel1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tableLayoutPanel1.Location = new System.Drawing.Point(0, 0);
            this.tableLayoutPanel1.Name = "tableLayoutPanel1";
            this.tableLayoutPanel1.Padding = new System.Windows.Forms.Padding(7);
            this.tableLayoutPanel1.RowCount = 2;
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 30F));
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Percent, 100F));
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 34F));
            this.tableLayoutPanel1.Size = new System.Drawing.Size(752, 250);
            this.tableLayoutPanel1.TabIndex = 0;
            // 
            // PropertyText
            // 
            this.PropertyText.Dock = System.Windows.Forms.DockStyle.Fill;
            this.PropertyText.Location = new System.Drawing.Point(10, 10);
            this.PropertyText.Name = "PropertyText";
            this.PropertyText.Size = new System.Drawing.Size(732, 20);
            this.PropertyText.TabIndex = 0;
            this.PropertyText.WordWrap = false;
            // 
            // MacrosList
            // 
            this.MacrosList.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.MacroColumn,
            this.ValueColumn});
            this.MacrosList.Dock = System.Windows.Forms.DockStyle.Fill;
            this.MacrosList.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            this.MacrosList.HideSelection = false;
            this.MacrosList.LabelWrap = false;
            this.MacrosList.Location = new System.Drawing.Point(10, 40);
            this.MacrosList.MultiSelect = false;
            this.MacrosList.Name = "MacrosList";
            this.MacrosList.ShowGroups = false;
            this.MacrosList.ShowItemToolTips = true;
            this.MacrosList.Size = new System.Drawing.Size(732, 166);
            this.MacrosList.Sorting = System.Windows.Forms.SortOrder.Ascending;
            this.MacrosList.TabIndex = 2;
            this.MacrosList.UseCompatibleStateImageBehavior = false;
            this.MacrosList.View = System.Windows.Forms.View.Details;
            this.MacrosList.DoubleClick += new System.EventHandler(this.MacrosList_DoubleClick);
            // 
            // MacroColumn
            // 
            this.MacroColumn.Text = "Macro";
            this.MacroColumn.Width = 249;
            // 
            // ValueColumn
            // 
            this.ValueColumn.Text = "Value";
            this.ValueColumn.Width = 407;
            // 
            // flowLayoutPanel1
            // 
            this.flowLayoutPanel1.Anchor = System.Windows.Forms.AnchorStyles.Right;
            this.flowLayoutPanel1.AutoSize = true;
            this.flowLayoutPanel1.AutoSizeMode = System.Windows.Forms.AutoSizeMode.GrowAndShrink;
            this.flowLayoutPanel1.Controls.Add(this.InsertFilenameBtn);
            this.flowLayoutPanel1.Controls.Add(this.InsertPathBtn);
            this.flowLayoutPanel1.Controls.Add(this.InsertMacroButton);
            this.flowLayoutPanel1.Controls.Add(this.OKButton);
            this.flowLayoutPanel1.Controls.Add(this.CancelBtn);
            this.flowLayoutPanel1.Location = new System.Drawing.Point(171, 212);
            this.flowLayoutPanel1.Name = "flowLayoutPanel1";
            this.flowLayoutPanel1.Size = new System.Drawing.Size(571, 28);
            this.flowLayoutPanel1.TabIndex = 3;
            // 
            // InsertFilenameBtn
            // 
            this.InsertFilenameBtn.Location = new System.Drawing.Point(3, 3);
            this.InsertFilenameBtn.Name = "InsertFilenameBtn";
            this.InsertFilenameBtn.Size = new System.Drawing.Size(119, 23);
            this.InsertFilenameBtn.TabIndex = 7;
            this.InsertFilenameBtn.Text = "Insert &Filename...";
            this.InsertFilenameBtn.UseVisualStyleBackColor = true;
            this.InsertFilenameBtn.Click += new System.EventHandler(this.InsertFilenameBtn_Click);
            // 
            // InsertPathBtn
            // 
            this.InsertPathBtn.Location = new System.Drawing.Point(128, 3);
            this.InsertPathBtn.Name = "InsertPathBtn";
            this.InsertPathBtn.Size = new System.Drawing.Size(119, 23);
            this.InsertPathBtn.TabIndex = 6;
            this.InsertPathBtn.Text = "Insert &Path...";
            this.InsertPathBtn.UseVisualStyleBackColor = true;
            this.InsertPathBtn.Click += new System.EventHandler(this.InsertPathBtn_Click);
            // 
            // InsertMacroButton
            // 
            this.InsertMacroButton.Location = new System.Drawing.Point(253, 3);
            this.InsertMacroButton.Name = "InsertMacroButton";
            this.InsertMacroButton.Size = new System.Drawing.Size(119, 23);
            this.InsertMacroButton.TabIndex = 3;
            this.InsertMacroButton.Text = "Insert &Macro";
            this.InsertMacroButton.UseVisualStyleBackColor = true;
            this.InsertMacroButton.Click += new System.EventHandler(this.InsertMacroButton_Click);
            // 
            // OKButton
            // 
            this.OKButton.DialogResult = System.Windows.Forms.DialogResult.OK;
            this.OKButton.ImeMode = System.Windows.Forms.ImeMode.NoControl;
            this.OKButton.Location = new System.Drawing.Point(378, 3);
            this.OKButton.Name = "OKButton";
            this.OKButton.Size = new System.Drawing.Size(92, 23);
            this.OKButton.TabIndex = 4;
            this.OKButton.Text = "OK";
            this.OKButton.UseVisualStyleBackColor = true;
            this.OKButton.Click += new System.EventHandler(this.OKButton_Click);
            // 
            // CancelBtn
            // 
            this.CancelBtn.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            this.CancelBtn.Location = new System.Drawing.Point(476, 3);
            this.CancelBtn.Name = "CancelBtn";
            this.CancelBtn.Size = new System.Drawing.Size(92, 23);
            this.CancelBtn.TabIndex = 5;
            this.CancelBtn.Text = "Cancel";
            this.CancelBtn.UseVisualStyleBackColor = true;
            // 
            // XSharpSLEPropertyForm
            // 
            this.AcceptButton = this.OKButton;
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.CancelButton = this.CancelBtn;
            this.CausesValidation = false;
            this.ClientSize = new System.Drawing.Size(752, 250);
            this.Controls.Add(this.tableLayoutPanel1);
            this.HelpButton = true;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "XSharpSLEPropertyForm";
            this.ShowIcon = false;
            this.ShowInTaskbar = false;
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.tableLayoutPanel1.ResumeLayout(false);
            this.tableLayoutPanel1.PerformLayout();
            this.flowLayoutPanel1.ResumeLayout(false);
            this.ResumeLayout(false);

		}

		#endregion

      private System.Windows.Forms.TableLayoutPanel tableLayoutPanel1;
      public System.Windows.Forms.TextBox PropertyText;
      private System.Windows.Forms.ListView MacrosList;
      private System.Windows.Forms.ColumnHeader MacroColumn;
      private System.Windows.Forms.ColumnHeader ValueColumn;
      private System.Windows.Forms.FlowLayoutPanel flowLayoutPanel1;
      private System.Windows.Forms.Button InsertMacroButton;
      private System.Windows.Forms.Button OKButton;
      private System.Windows.Forms.Button CancelBtn;
      private System.Windows.Forms.Button InsertFilenameBtn;
      private System.Windows.Forms.Button InsertPathBtn;

   }
}