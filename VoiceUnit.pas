unit VoiceUnit;
interface
uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, Menus, Grids, ValEdit, StdCtrls, ComCtrls, ExtCtrls, KiwiTypes, CompUnit, MMSystem;

//=============================================================================
//                  Kiwi Format Explorer
//=============================================================================
//                  VOICE DATA FRAME
//=============================================================================
type
 LN_Voice_Offset_Management_Record = record
 Manufacturer: TLN_MID;
 Usage:  WORD;
 Speaker_Code: BYTE;
 Reproduction: BYTE;
 Numberof_Voices: WORD;
 Offsetto_Voice_Offset_Table: Int64;
 Voice_Offset_Table_Size: DWORD;
 end;

LN_Voice_Offset_Management_Table  = record
	Numberof_Records: WORD;
   Records: array of LN_Voice_Offset_Management_Record;
end;

LN_Voice_Distribution_Header = record
 Size: DWORD;
 Numberof_Languages: WORD;
// Proper_Voice_real_data_size: DWORD;
end;

LN_Voice_Offset_Record = record
	Offsetto_Real_Data: Int64;
   Real_Data_Size: DWORD;
end;

LN_Voice_Offset_Table = record
	Voice_Data_ID: DWORD;
   Numberof_Phrases: WORD;
   Phrases: array of LN_Voice_Offset_Record;
end;

LN_Sound = record
	Data: LN_Voice_Offset_Table;
   BufferSize: DWORD;
   Buffer: array of SMALLINT;
end;

TLN_VoiceManager = class(TLN_Manager)
private
    fVoice: LN_Voice_Distribution_Header;
    fPrevSample, fPrevPrevSample: Integer;
    procedure Read_Voice_Distribution_Header(var aParam: LN_Voice_Distribution_Header);
public
    constructor Create(aFileName: TFileName);  overload;
    constructor Create(aFile: TLN_DecompFileStream; aStartOffset: Int64); overload;
    procedure Read_Voice_Offset_Management_Table(aLangNumber: WORD; var aParam: LN_Voice_Offset_Management_Table);
    function Get_Next_Voice_Table_Offset(const aOffset: Int64): Int64;
    procedure Read_Voice_Offset_Table(const aOffset: Int64; var aParam: LN_Voice_Offset_Table);
    procedure ReadSoundGroup(aOutFile: TStream);
    function ReadSoundData(const aOffset: Int64; aOutFile: TStream): DWORD;
    function CountSoundDataSize(const aOffset: Int64): DWORD;
    procedure PlaySoundData(const aOffset: Int64);
    procedure PlayNaturalVoiceData(const aOffset: Int64; aSize: DWORD);
    property Header: LN_Voice_Distribution_Header read fVoice;
end;

implementation
//=============================================================================
{ TLN_VoiceManager }      {VOICEDAT.KWI}
//=============================================================================
constructor TLN_VoiceManager.Create(aFileName: TFileName);
begin
	inherited Create(aFileName);
   Read_Voice_Distribution_Header(fVoice);
end;
//=============================================================================
constructor TLN_VoiceManager.Create(aFile: TLN_DecompFileStream; aStartOffset: Int64);
begin
   inherited Create(aFile, aStartOffset);
   if DataValid then
   	Read_Voice_Distribution_Header(fVoice);
end;
//=============================================================================
function TLN_VoiceManager.Get_Next_Voice_Table_Offset(const aOffset: Int64): Int64;
begin
	Result :=  aOffset + 6+  LN_FileReadWord(FileStream, aOffset + 4) * 6;
end;
//=============================================================================
procedure TLN_VoiceManager.Read_Voice_Distribution_Header(var aParam: LN_Voice_Distribution_Header);
begin
	aParam.Size := LN_FileReadDword(FileStream, StartOffset) * 2;
   aParam.Numberof_Languages := LN_FileReadWord(FileStream, StartOffset + 4);
//   aParam.Proper_Voice_real_data_size := LN_FileReadDword(FileStream, StartOffset + aParam.Size - 4) * 2;
   SetDataValid(aParam.Numberof_Languages < 32);
end;
//=============================================================================
procedure TLN_VoiceManager.Read_Voice_Offset_Management_Table(aLangNumber: WORD;  var aParam: LN_Voice_Offset_Management_Table);
var faAddress: Int64;
	aCount: Integer;
begin
   aCount := 0;
   faAddress := StartOffset + 6;
   while aCount < aLangNumber  do
   	begin
		faAddress := faAddress + 2 + LN_FileReadWord(FileStream, faAddress) * 26;
      Inc(aCount);
      end;
   aParam.Numberof_Records := LN_FileReadWord(FileStream, faAddress);
   SetLength(aParam.Records, aParam.Numberof_Records);
   faAddress := faAddress + 2;
   for aCount := 0 to aParam.Numberof_Records - 1 do
   	begin
      aParam.Records[aCount].Manufacturer := LN_FileReadMID(FileStream, faAddress);
      aParam.Records[aCount].Usage := LN_FileReadWord(FileStream, faAddress + 12);
      aParam.Records[aCount].Speaker_Code := LN_FileReadByte(FileStream, faAddress + 14);
      aParam.Records[aCount].Reproduction := LN_FileReadByte(FileStream, faAddress + 15);
      aParam.Records[aCount].Numberof_Voices := LN_FileReadWord(FileStream, faAddress + 16);
      aParam.Records[aCount].Offsetto_Voice_Offset_Table := StartOffset + LN_FileReadDword(FileStream, faAddress + 18) * 2;
      aParam.Records[aCount].Voice_Offset_Table_Size := LN_FileReadDword(FileStream, faAddress + 22) * 2;
      faAddress := faAddress + 26;
      end;
end;
//=============================================================================
procedure TLN_VoiceManager.Read_Voice_Offset_Table(const aOffset: Int64; var aParam: LN_Voice_Offset_Table);
var i: Integer;
begin
	aParam.Voice_Data_ID := LN_FileReadDword(FileStream, aOffset);
   aParam.Numberof_Phrases := LN_FileReadWord(FileStream, aOffset + 4);
   SetLength(aParam.Phrases, aParam.Numberof_Phrases);
   for i := 0 to aParam.Numberof_Phrases - 1 do
   	begin
   	aParam.Phrases[i].Offsetto_Real_Data := StartOffset + LN_FileReadDword(FileStream, aOffset + 6 + 6 * i) * 2;
      aParam.Phrases[i].Real_Data_Size := LN_FileReadWord(FileStream, aOffset + 10 + 6 * i) * 2;
      end;
end;
//=============================================================================
//  Audio codec -> Decode CD-I ADPCM
procedure TLN_VoiceManager.ReadSoundGroup(aOutFile: TStream);
var SoundGroup:  packed record
 		Reserved1: DWORD;
 		Param: array [0..7] of BYTE;
 		Reserved2: DWORD;
 		Data: array [0..111] of  BYTE;
 		end;
   j, k: Integer;
   aNible: SHORTINT;
   aTemp: SMALLINT;
   Idx: BYTE;
   Range, Filter: SHORTINT;
   NewSample: Integer;
   OutWord: SMALLINT;

const Koef1: array [0..3] of BYTE = (0, $3C, $73, $62);  // 0, 0.9375, 1.796875, 1.53125
const Koef2: array [0..3] of BYTE = (0, 0, $34, $37);    // 0, 0, -0.8125, -0.859375

begin
   FileStream.Read(SoundGroup, Sizeof(SoundGroup));
   for j := 0 to 7 do
   	begin
      Filter := (SoundGroup.Param[j] shr 4) and $3;
      Range := 12  - (SoundGroup.Param[j]  and $F);

   	for k := 0 to 27 do
    		begin
      	Idx := 4 * k  + ((j shr 1) and 3);
      	if (j and 1) = 0 then
      		aNible := SoundGroup.Data[Idx] shl 4
      	else
         	aNible := SoundGroup.Data[Idx] and $F0;
         aNible := aNible shr 4;

         aTemp := aNible  shl Range;
         NewSample := aTemp + (fPrevSample * Koef1[Filter] div 64);
      	NewSample := NewSample - (fPrevPrevSample * Koef2[Filter] div 64);
      	fPrevPrevSample := fPrevSample;
         fPrevSample := NewSample;

   		if newSample > 32767 then
   			newSample := 32767
   		else if newSample < -32768 then
   			newSample := -32768;

      	OutWord := NewSample;
      	if aOutFile <> nil then
      		aOutFile.Write(OutWord, 2);
      	end;
      end;
end;
//=============================================================================
function TLN_VoiceManager.ReadSoundData(const aOffset: Int64; aOutFile: TStream): DWORD;
var i, j, aCount: Integer;
	aVoiceOffsetTable: LN_Voice_Offset_Table;
begin
	Read_Voice_Offset_Table(aOffset, aVoiceOffsetTable);
   Result := 0;
   for i := 0 to aVoiceOffsetTable.Numberof_Phrases - 1 do
   	begin
   	FileStream.Position := aVoiceOffsetTable.Phrases[i].Offsetto_Real_Data;
      Result := Result + aVoiceOffsetTable.Phrases[i].Real_Data_Size;
      aCount  := aVoiceOffsetTable.Phrases[i].Real_Data_Size div 128;
      fPrevSample := 0;
      fPrevPrevSample := 0;
      for j := 0 to aCount - 1 do
      	ReadSoundGroup(aOutFile);
      end;
end;
//=============================================================================
function TLN_VoiceManager.CountSoundDataSize(const aOffset: Int64): DWORD;
var i: Integer;
	aVoiceOffsetTable: LN_Voice_Offset_Table;
begin
	Read_Voice_Offset_Table(aOffset, aVoiceOffsetTable);
   Result := 0;
   for i := 0 to aVoiceOffsetTable.Numberof_Phrases - 1 do
      Result := Result + aVoiceOffsetTable.Phrases[i].Real_Data_Size;
end;
//=============================================================================
procedure TLN_VoiceManager.PlaySoundData(const aOffset: Int64);
var
  WaveFormatEx: TWaveFormatEx;
  MemStream: TMemoryStream;
  WaveFormatExSize, DataCount, RiffCount: integer;

const
  Mono: Word = $0001;
  SampleRate: Integer = 18900; // 8000, 11025, 22050, or 44100
  RiffId: string = 'RIFF';
  WaveId: string = 'WAVE';
  FmtId: string = 'fmt ';
  DataId: string = 'data';
begin
	MemStream := TMemoryStream.Create;
   try
    	MemStream.Position := 0;
    	WaveFormatEx.wFormatTag := WAVE_FORMAT_PCM;
    	WaveFormatEx.nChannels := Mono;
    	WaveFormatEx.nSamplesPerSec := SampleRate;
    	WaveFormatEx.wBitsPerSample := $0010;
    	WaveFormatEx.nBlockAlign := (WaveFormatEx.nChannels * WaveFormatEx.wBitsPerSample) div 8;
    	WaveFormatEx.nAvgBytesPerSec := WaveFormatEx.nSamplesPerSec * WaveFormatEx.nBlockAlign;
    	WaveFormatEx.cbSize := 0;
    	{Calculate length of sound data and of file data}
    	DataCount := (CountSoundDataSize(aOffset) div 128) * 448; //  sound data
    	WaveFormatExSize := SizeOf(TWaveFormatEx) + WaveFormatEx.cbSize;
    	RiffCount := Length(WaveId) + Length(FmtId) + SizeOf(DWORD) +
      WaveFormatExSize + Length(DataId) + SizeOf(DWORD) + DataCount; // file data
    	{write out the wave header}
    	MemStream.Write(RiffId[1], 4); // 'RIFF'
    	MemStream.Write(RiffCount, SizeOf(DWORD)); // file data size
    	MemStream.Write(WaveId[1], Length(WaveId)); // 'WAVE'
    	MemStream.Write(FmtId[1], Length(FmtId)); // 'fmt '
    	MemStream.Write(WaveFormatExSize, SizeOf(DWORD)); // TWaveFormat data size
    	MemStream.Write(WaveFormatEx, WaveFormatExSize); // WaveFormatEx record
    	MemStream.Write(DataId[1], Length(DataId)); // 'data'
    	MemStream.Write(DataCount, SizeOf(DWORD)); // sound data size

    	ReadSoundData(aoffset, MemStream);
    	{now play the sound}
    	SndPlaySound(MemStream.Memory, SND_MEMORY or SND_ASYNC);
   finally
    	MemStream.Free;
  	end;
end;
//=============================================================================
procedure TLN_VoiceManager.PlayNaturalVoiceData(const aOffset: Int64; aSize: DWORD);
var
  	WaveFormatEx: TWaveFormatEx;
  	MemStream: TMemoryStream;
  	WaveFormatExSize, DataCount, RiffCount: integer;
	i, aCount: Integer;

const
  Mono: Word = $0001;
  SampleRate: Integer = 18900; // 8000, 11025, 22050, or 44100
  RiffId: string = 'RIFF';
  WaveId: string = 'WAVE';
  FmtId: string = 'fmt ';
  DataId: string = 'data';
begin
	if (aOffset + aSize) > FileStream.Size then
      	EXIT;
      
   MemStream := TMemoryStream.Create;
   try
    	MemStream.Position := 0;
    	WaveFormatEx.wFormatTag := WAVE_FORMAT_PCM;
    	WaveFormatEx.nChannels := Mono;
    	WaveFormatEx.nSamplesPerSec := SampleRate;
    	WaveFormatEx.wBitsPerSample := $0010;
    	WaveFormatEx.nBlockAlign := (WaveFormatEx.nChannels * WaveFormatEx.wBitsPerSample) div 8;
    	WaveFormatEx.nAvgBytesPerSec := WaveFormatEx.nSamplesPerSec * WaveFormatEx.nBlockAlign;
    	WaveFormatEx.cbSize := 0;
    	{Calculate length of sound data and of file data}
    	DataCount := (aSize div 128) * 448; //  sound data
    	WaveFormatExSize := SizeOf(TWaveFormatEx) + WaveFormatEx.cbSize;
    	RiffCount := Length(WaveId) + Length(FmtId) + SizeOf(DWORD) +
      WaveFormatExSize + Length(DataId) + SizeOf(DWORD) + DataCount; // file data
    	{write out the wave header}
    	MemStream.Write(RiffId[1], 4); // 'RIFF'
    	MemStream.Write(RiffCount, SizeOf(DWORD)); // file data size
    	MemStream.Write(WaveId[1], Length(WaveId)); // 'WAVE'
    	MemStream.Write(FmtId[1], Length(FmtId)); // 'fmt '
    	MemStream.Write(WaveFormatExSize, SizeOf(DWORD)); // TWaveFormat data size
    	MemStream.Write(WaveFormatEx, WaveFormatExSize); // WaveFormatEx record
    	MemStream.Write(DataId[1], Length(DataId)); // 'data'
    	MemStream.Write(DataCount, SizeOf(DWORD)); // sound data size

    	FileStream.Position := aOffset;
      aCount  := aSize div 128;
      fPrevSample := 0;
      fPrevPrevSample := 0;
      for  i := 0 to aCount - 1 do
      	ReadSoundGroup(MemStream);
    	{now play the sound}
    	SndPlaySound(MemStream.Memory, SND_MEMORY or SND_ASYNC);
   finally
    	MemStream.Free;
  	end;
end;
//=============================================================================
end.
