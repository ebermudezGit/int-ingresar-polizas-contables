SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/**************** DROP IF EXISTS ****************/
IF EXISTS (SELECT name FROM sysobjects WHERE name = 'CUP_SPI_wsPolizasContables_Insertar') 
  DROP PROCEDURE  CUP_SPI_wsPolizasContables_Insertar
GO

/* =============================================
  
  Created by:    Enrique Sierra Gtez
  Creation Date: 2017-03-16

  Description: Procedimiento encargado de insertar
  las polizas contables que se ingresaran a Intelisis
  de parte de otros sistemas mediante el llamado de un
  web service.

============================================= */

CREATE PROCEDURE [dbo].CUP_SPI_wsPolizasContables_Insertar    
    @PolizaID INT OUTPUT         
AS BEGIN TRY
  DECLARE 
    @CUP_Proceso INT = 17,
    @HOY DATETIME = GETDATE()
 
  INSERT INTO 
    Cont 
  (
    CUP_Origen,
    CUP_OrigenID,
    Mov,
    FechaEmision,
    FechaContable,
    FechaRegistro,
    Sucursal,
    Concepto,
    Referencia,
    Usuario,
    Moneda,
    TipoCambio,
    Estatus,
    SucursalOrigen
  )
  SELECT 
    CUP_Origen = @CUP_Proceso,
    CUP_OrigenId = Sistema,
    Mov = Tipo,
    FechaEmision = CAST(@HOY AS DATE),
    FechaContable = CAST(FechaContable AS DATE),
    FechaRegistro = @HOY,
    Sucursal = SucursalContable,
    Concepto = NULLIF(Concepto,''),
    Referencia = NULLIF(Referencia,''),
    Usuario = 'PRODAUT',
    Moneda = 'Pesos',
    TipoCambio = 1,
    Estatus = 'SINAFECTAR',
    SucursalOrigen = SucursalContable
  FROM 
    #tmp_wsPolizasIntelisis_Header

  SET @PolizaID = SCOPE_IDENTITY()

  IF @PolizaID IS NOT NULL
  BEGIN
    INSERT INTO 
      ContD
    (
      ID
      ,Renglon
      ,RenglonSub
      ,Cuenta
      ,SubCuenta
      ,Concepto
      ,Debe
      ,Haber
      ,Sucursal
      ,SucursalContable
      ,SucursalOrigen
    )
   SELECT 
    @PolizaID
    ,Renglon = CAST(  2048 
                      * ROW_NUMBER() OVER (
                                            ORDER BY
                                              detalle.Cuenta,
                                              detalle.Subcuenta
                                            ) 
                       AS FLOAT) --(de 2048 en 2048)
    , RenglonSub= ROW_NUMBER() OVER (
                                    PARTITION BY
                                      detalle.Cuenta,
                                      detalle.Subcuenta 
                                    ORDER BY
                                      su.Subcuenta
                                    ) - 1
    ,detalle.Cuenta
    ,detalle.SubCuenta
    ,Concepto = NULLIF(detalle.Concepto,'')
    ,detalle.Debe
    ,detalle.Haber
    ,cabecero.SucursalContable
    ,cabecero.SucursalContable
    ,cabecero.SucursalContable
    --,MonedaOriginal
    --,TipoCambioOriginal
    FROM 
      #tmp_wsPolizasIntelisis_Header cabecero
    JOIN #tmp_wsPolizasIntelisis_Records detalle ON detalle.Cuenta = detalle.Cuenta
  END 
  ELSE 
  BEGIN
    INSERT INTO #tmp_wsPolizasIntelisis_Messages ( NUM , [Description] )
    VALUES ( '3', 'Eror al insertar la p�liza contable.')
  END

  RETURN 

END TRY
BEGIN CATCH
 IF OBJECT_ID('tempdb..#tmp_wsPolizasIntelisis_Messages') IS NOT NULL
 BEGIN
    INSERT INTO #tmp_wsPolizasIntelisis_Messages
    ( 
      NUM, 
      [Description] 
    )
    SELECT 
      Num =  ERROR_NUMBER()
     ,[Description] = ERROR_MESSAGE()
 END
 ELSE
 BEGIN
    SELECT
    Num = ERROR_NUMBER()
    ,[Description] = ERROR_MESSAGE()
    ,ID = ''
    ,Mov = ''
    ,MovID = ''
  END
  
END CATCH