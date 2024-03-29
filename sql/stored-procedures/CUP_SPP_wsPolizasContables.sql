SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/**************** DROP IF EXISTS ****************/
IF EXISTS (SELECT name FROM sysobjects WHERE name = 'CUP_SPP_wsPolizasContables') 
  DROP PROCEDURE  CUP_SPP_wsPolizasContables
GO

/* =============================================
  
  Created by:    Enrique Sierra Gtez
  Creation Date: 2017-03-16

  Description: Procedimiento maestro encargado
  de interpretar e ingresar polizas contables
  a Intelisis provenientes de otros sistemas
  mediante el llamado a un web service.

============================================= */

CREATE PROCEDURE [dbo].CUP_SPP_wsPolizasContables
(
 @Poliza XML(JournalEntrySchema)
)                
AS BEGIN TRY
  DECLARE 
    @PolizaID INT,
    @Ok INT,
    @OkRef VARCHAR(255)

  -- Datos del cabecero de la poliza
  IF OBJECT_ID('tempdb..#tmp_wsPolizasIntelisis_Header') IS NOT NULL
    DROP TABLE #tmp_wsPolizasIntelisis_Header

  CREATE TABLE #tmp_wsPolizasIntelisis_Header
  (
    Sistema INT  NULL,
    Tipo   VARCHAR(20)  NULL,
    FechaContable DATE,
    SucursalContable   INT NULL,
    Concepto VARCHAR(50) NULL,
    Referencia VARCHAR(50) NULL
  )

  INSERT INTO #tmp_wsPolizasIntelisis_Header
  (
    Sistema,
    Tipo,
    FechaContable,
    SucursalContable,
    Concepto,
    Referencia
  )
   SELECT  
    Sistema            = c.value('@System','INT')
    ,Tipo              = c.value('(Type)','VARCHAR(20)')
    ,FechaContable     = c.value('(EffectiveDate)[1]','DATE')
    ,SucursalContable  = c.value('(Branch)[1]','INT')
    ,Concepto          = c.value('(Concept)[1]','VARCHAR(50)')
    ,Referencia        = c.value('(Reference)[1]','VARCHAR(50)')
  FROM
    @Poliza.nodes('/JournalEntry') AS R(c)

  -- Datos del detalle de la poliza
  IF OBJECT_ID('tempdb..#tmp_wsPolizasIntelisis_Records') IS NOT NULL
    DROP TABLE #tmp_wsPolizasIntelisis_Records

  CREATE TABLE #tmp_wsPolizasIntelisis_Records
  (
    Cuenta CHAR(20) NOT NULL,
    SubCuenta VARCHAR(50) NULL,
    Concepto VARCHAR(50) NULL,
    Debe DECIMAL(18,4) NOT NULL,
    Haber DECIMAL(18,4) NOT NULL,
    MonedaOriginal CHAR(10) NULL,
    TipoCambioOriginal FLOAT NULL
  )

  CREATE NONCLUSTERED INDEX IX_#tmp_wsPolizasIntelisis_Records_Cuenta_Subcuenta
    ON #tmp_wsPolizasIntelisis_Records ( Cuenta, SubCuenta )
  INCLUDE 
  (
    Concepto,
    Debe,
    Haber,
    MonedaOriginal,
    TipoCambioOriginal
  )

  CREATE NONCLUSTERED INDEX IX_#tmp_wsPolizasIntelisis_Records_MonedaOriginal
    ON #tmp_wsPolizasIntelisis_Records ( MonedaOriginal)
  INCLUDE 
  (
    Cuenta,
    SubCuenta,
    Concepto,
    Debe,
    Haber,
    TipoCambioOriginal
  )

  INSERT INTO #tmp_wsPolizasIntelisis_Records
  (
    Cuenta,
    SubCuenta,
    Debe,
    Haber,
    Concepto,
    MonedaOriginal,
    TipoCambioOriginal
  )
  SELECT
    Cuenta              = c.value('(Account)[1]','varchar(100)')
    ,SubCuenta          = c.value('(CostCenter)[1]','VARCHAR(50)')
    ,Debe               = c.value('(Debit)[1]','DECIMAL(18,4)')
    ,Haber              = c.value('(Credit)[1]','DECIMAL(18,4)')
    ,Concepto           = c.value('(Concept)[1]','VARCHAR(50)')
    ,MonedaOriginal     = c.value('(OriginalCurrency)[1]','CHAR(10)')
    ,TipoCambioOriginal = c.value('(OriginalExchangeRate)[1]','FLOAT') 
  FROM
    @Poliza.nodes('/JournalEntry/Records/Record') AS R(c)

  -- Contenedor de los mensajes de respuesta del proceso. 
  IF OBJECT_ID('tempdb..#tmp_wsPolizasIntelisis_Messages') IS NOT NULL
    DROP TABLE #tmp_wsPolizasIntelisis_Messages

  CREATE TABLE #tmp_wsPolizasIntelisis_Messages
  (
    Num INT NOT NULL,
    [Description] VARCHAR(255) NOT NULL,
    ID INT NULL,
    Mov VARCHAR(20) NULL,
    MovID VARCHAR(20) NULL
  )

  -- Validacion de la informacion
  EXEC CUP_SPP_wsPolizasContables_Validar
   
  IF NOT EXISTS(SELECT
                  [Description]
                FROM
                  #tmp_wsPolizasIntelisis_Messages 
                WHERE 
                  Num > 0)
  BEGIN TRY 

    BEGIN TRAN wsCont
    -- Creacion de la poliza
    EXEC CUP_SPI_wsPolizasContables_Insertar @PolizaID OUTPUT

    -- Verificacion y afectacion de la poliza
    IF @PolizaID IS NOT NULL
    BEGIN
      EXEC CUP_SPP_wsPolizasContables_Afectar
        @VerificarSinAfectar = 1,
        @Ok  = @Ok OUTPUT,
        @OkRef  = @OK OUTPUT
    END 
    

    IF XACT_STATE() = 1 
      COMMIT TRAN wsCont

  END TRY 
  BEGIN CATCH 
    IF XACT_STATE() <> 0  
      ROLLBACK TRAN wsCont

    INSERT INTO #tmp_wsPolizasIntelisis_Messages ( NUM , [Description] )
    VALUES ( ERROR_NUMBER(), ERROR_NUMBER())
    
  END CATCH

  -- Termino del proceso, preparacion y regreso de los mensajes.
  IF NOT EXISTS(SELECT [Description] FROM #tmp_wsPolizasIntelisis_Messages)
    INSERT INTO #tmp_wsPolizasIntelisis_Messages ( NUM , [Description] )
    VALUES ( '2', 'Unhandled Error... Please contact the CML-Planos team')

  SELECT
    Num
    ,[Description] = ISNULL([Description],'')
    ,ID = ISNULL(CAST(ID AS VARCHAR(30)),'')
    ,Mov = ISNULL(Mov,'')
    ,MovID = ISNULL(MovID,'')
  FROM
    #tmp_wsPolizasIntelisis_Messages

END TRY
BEGIN CATCH
  SELECT
    Num = ERROR_NUMBER()
    ,[Description] = ERROR_MESSAGE()
    ,ID = ''
    ,Mov = ''
    ,MovID = ''
END CATCH