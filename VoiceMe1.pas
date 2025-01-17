unit VoiceMe1;
interface
uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, Menus, Grids, ValEdit, StdCtrls, ComCtrls, ExtCtrls, KiwiTypes, CompUnit, MMSystem;

//=============================================================================
//                  Kiwi Format Explorer
//=============================================================================
//                  VOICE   ME 001
//=============================================================================
type
LN_VoiceMe1_Language = record
 Address_B1: Int64;
 Sizeof_B1: DWORD;
 Address_B2: Int64;
 Sizeof_B2: DWORD;
 Address_B3: Int64;
 Sizeof_B3: DWORD;
 Address_B4: Int64;
 Sizeof_B4: DWORD;
 Language_ID: BYTE;
 Voice_ID: BYTE;
end;

LN_VoiceMe1_Header = record
Header_Size: DWORD;
NumberofLanguages: WORD;
LangArray: array of LN_VoiceMe1_Language;
end;

TLN_VoiceOffsetRecord = record
 Lang: WORD;
 Rec_ID: DWORD;
 Address: Int64;
 Size: DWORD;
 Mode: BYTE;
 Chanels: BYTE;
 Frequency: WORD;
end;

TLN_VoiceMe1Manager = class(TLN_Manager)
private
//    FileStream: TLN_DecompFileStream;
//    fStartOffset: Int64;
//    fFileOwner: boolean;
    fVoice: LN_VoiceMe1_Header;
    fPrevSample, fPrevPrevSample: Integer;
    procedure Read_VoiceMe1_Header(var aParam: LN_VoiceMe1_Header);
    procedure ReadSoundGroup(aOutFile: TStream);

public
    constructor Create(aFileName: TFileName);  overload;
    constructor Create(aFile: TLN_DecompFileStream; aStartOffset: Int64); overload;
//    destructor Destroy; override;
    function Get_NumberofRecords(LangIndex: WORD): WORD;
    procedure Read_VoiceOffsetRecord(LangIndex, RecIndex: WORD; var aParam: TLN_VoiceOffsetRecord);
    function ReadSoundData(LangIndex, RecIndex: WORD; aOutFile: TStream): DWORD;
    property Header: LN_VoiceMe1_Header read fVoice;
    procedure PlaySoundData(LangIndex, RecIndex: WORD);
//    property FileStream: TLN_DecompFileStream read FileStream;
end;




implementation
//=============================================================================
{ TLN_VoiceMe1Manager }         {VOICE001.ME}
//=============================================================================
constructor TLN_VoiceMe1Manager.Create(aFileName: TFileName);
begin
	inherited Create(aFileName);
   Read_VoiceMe1_Header(fVoice);
end;
//=============================================================================
constructor TLN_VoiceMe1Manager.Create(aFile: TLN_DecompFileStream; aStartOffset: Int64);
begin
   inherited Create(aFile, aStartOffset);
   Read_VoiceMe1_Header(fVoice);
end;
//=============================================================================
function TLN_VoiceMe1Manager.Get_NumberofRecords(LangIndex: WORD): WORD;
begin
	Result := LN_FileReadWord(FileStream, fVoice.LangArray[LangIndex].Address_B1);
end;
//=============================================================================
procedure TLN_VoiceMe1Manager.Read_VoiceMe1_Header(var aParam: LN_VoiceMe1_Header);
var i: Integer;
begin
	aParam.Header_Size := LN_FileReadWord(FileStream, StartOffset) * 2;
   aParam.NumberofLanguages := (aParam.Header_Size - 2) div $40;
   SetDataValid(aParam.NumberofLanguages < 32);
   if not DataValid  then EXIT;
   
   SetLength(aParam.LangArray, aParam.NumberofLanguages);
   for i := 0 to aParam.NumberofLanguages - 1 do
   	begin
      aParam.LangArray[i].Address_B1 :=  OffsetFromD(LN_FileReadDword(FileStream, StartOffset + 2 + i * $40), StartOffset);
      aParam.LangArray[i].Sizeof_B1 :=  LN_FileReadWord(FileStream, StartOffset + 6 + i * $40) * 2;
      aParam.LangArray[i].Address_B2 :=  OffsetFromD(LN_FileReadDword(FileStream, StartOffset + 8 + i * $40), StartOffset);
      aParam.LangArray[i].Sizeof_B2 :=  LN_FileReadWord(FileStream, StartOffset + 12 + i * $40) * 2;
      aParam.LangArray[i].Address_B3 :=  OffsetFromD(LN_FileReadDword(FileStream, StartOffset + 14 + i * $40), StartOffset);
      aParam.LangArray[i].Sizeof_B3 :=  LN_FileReadWord(FileStream, StartOffset + 18 + i * $40) * 2;
      aParam.LangArray[i].Address_B4 :=  OffsetFromD(LN_FileReadDword(FileStream, StartOffset + 20 + i * $40), StartOffset);
      aParam.LangArray[i].Sizeof_B4 :=  LN_FileReadDword(FileStream, StartOffset + 24 + i * $40) * 2;
      aParam.LangArray[i].Language_ID := LN_FileReadByte(FileStream, StartOffset + 28 + i * $40);
      aParam.LangArray[i].Voice_ID := LN_FileReadByte(FileStream, StartOffset + 29 + i * $40);
      end;
end;
//=============================================================================
procedure TLN_VoiceMe1Manager.Read_VoiceOffsetRecord(LangIndex, RecIndex: WORD; var aParam: TLN_VoiceOffsetRecord);
var aOffset: Int64;
begin
	aOffset := fVoice.LangArray[LangIndex].Address_B1 + 2 + RecIndex * 18;
   aParam.Lang := LN_FileReadWord(FileStream, aOffset);
   aParam.Rec_ID := LN_FileReadDword(FileStream, aOffset + 2);
   aParam.Address := OffsetFromD(LN_FileReadDword(FileStream, aOffset + 6),  fVoice.LangArray[LangIndex].Address_B4);
   aParam.Size := LN_FileReadDword(FileStream, aOffset + 10) * 2;
   aParam.Mode := LN_FileReadByte(FileStream, aOffset + 14);
   aParam.Chanels := LN_FileReadByte(FileStream, aOffset + 15);
   aParam.Frequency := LN_FileReadWord(FileStream, aOffset + 16); // * 2;
end;
//=============================================================================
//  Audio codec -> Decode CD-I ADPCM not Sony/Phillips standard
procedure TLN_VoiceMe1Manager.ReadSoundGroup(aOutFile: TStream);
var SoundGroup:  packed record
 		Param: BYTE;
      Data: array [0..14] of  BYTE;
 		end;
   k: Integer;
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
      Filter := SoundGroup.Param and $3;
      Range := 12  - ((SoundGroup.Param shr 4)  and $F);

   	for k := 0 to 29 do
    		begin
         Idx := k div 2;
      	if (k and 1) <> 0 then
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
//=============================================================================
function TLN_VoiceMe1Manager.ReadSoundData(LangIndex, RecIndex: WORD; aOutFile: TStream): DWORD;
var  j, aCount: Integer;
	aParam: TLN_VoiceOffsetRecord;
begin
	Read_VoiceOffsetRecord(LangIndex, RecIndex, aParam);
   Result := aParam.Size;
   FileStream.Position := aParam.Address;
   aCount  := aParam.Size div 16;
   fPrevSample := 0;
   fPrevPrevSample := 0;
   for j := 0 to aCount - 1 do
      	ReadSoundGroup(aOutFile);
end;
//=============================================================================
procedure TLN_VoiceMe1Manager.PlaySoundData(LangIndex, RecIndex: WORD);
var aParam: TLN_VoiceOffsetRecord;
  WaveFormatEx: TWaveFormatEx;
  MemStream: TMemoryStream;
  WaveFormatExSize, DataCount, RiffCount: integer;
const
//  Mono: Word = $0001;
//  SampleRate: Integer = 18900; // 8000, 11025, 22050, or 44100
  RiffId: string = 'RIFF';
  WaveId: string = 'WAVE';
  FmtId: string = 'fmt ';
  DataId: string = 'data';
begin
	Read_VoiceOffsetRecord(LangIndex, RecIndex, aParam);
   try
    	MemStream := TMemoryStream.Create;
    	MemStream.Position := 0;
    	WaveFormatEx.wFormatTag := WAVE_FORMAT_PCM;
    	WaveFormatEx.nChannels := aParam.Chanels;
    	WaveFormatEx.nSamplesPerSec :=  aParam.Frequency;
    	WaveFormatEx.wBitsPerSample := $0010;
    	WaveFormatEx.nBlockAlign := (WaveFormatEx.nChannels * WaveFormatEx.wBitsPerSample) div 8;
    	WaveFormatEx.nAvgBytesPerSec := WaveFormatEx.nSamplesPerSec * WaveFormatEx.nBlockAlign;
    	WaveFormatEx.cbSize := 0;
    	{Calculate length of sound data and of file data}
    	DataCount := (aParam.Size div 16) * 60; //  sound data
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

    	//  Read Sound Data
    	ReadSoundData(LangIndex, RecIndex, MemStream);
    	{now play the sound}
    	sndPlaySound(MemStream.Memory, SND_MEMORY or SND_ASYNC);
   finally
    	MemStream.Free;
  	end;
end;
//=============================================================================

end.
