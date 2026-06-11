-- ============================================================
-- SP_ASISTENCIA: Procesamiento de marcas de asistencia
-- Calcula horas ordinarias, extras normales y extras dobles.
-- ============================================================

USE PlanillaObrera;
GO

-- ============================================================
-- Función auxiliar: ¿Es feriado o domingo una fecha?
-- ============================================================
IF OBJECT_ID('dbo.fn_EsFeriadoODomingo', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_EsFeriadoODomingo;
GO
CREATE FUNCTION dbo.fn_EsFeriadoODomingo(@fecha DATE)
RETURNS BIT
AS
BEGIN
    -- DATEPART: 1=domingo, 7=sábado en SQL Server (datefirst=7 default)
    IF DATEPART(WEEKDAY, @fecha) = 1  RETURN 1;  -- domingo
    IF EXISTS (SELECT 1 FROM dbo.Feriado WHERE Fecha = @fecha) RETURN 1;
    RETURN 0;
END;
GO

-- ============================================================
-- SP: Registrar bitácora (helper interno)
-- ============================================================
IF OBJECT_ID('sp_RegistrarEvento', 'P') IS NOT NULL DROP PROCEDURE sp_RegistrarEvento;
GO
CREATE PROCEDURE sp_RegistrarEvento
    @IdUsuario      INT,
    @IdTipoEvento   INT,
    @IPOrigen       VARCHAR(45),
    @Parametros     NVARCHAR(MAX) = NULL,
    @DatosAntes     NVARCHAR(MAX) = NULL,
    @DatosDespues   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.BitacoraEvento (IdUsuario, IdTipoEvento, IPOrigen, FechaHora, Parametros, DatosAntes, DatosDespues)
    VALUES (@IdUsuario, @IdTipoEvento, @IPOrigen, GETDATE(), @Parametros, @DatosAntes, @DatosDespues);
END;
GO
-- ============================================================
-- SP: Procesar una marca de asistencia individual
-- Parámetros:
--   @ValorDocumento  : cédula del empleado (mapeo desde XML)
--   @FechaHoraEntrada / @FechaHoraSalida : DATETIME
--   @IdUsuarioSistema: usuario del proceso de simulación
--   @IPOrigen        : IP del proceso
-- ============================================================
IF OBJECT_ID('sp_ProcesarAsistencia', 'P') IS NOT NULL DROP PROCEDURE sp_ProcesarAsistencia;
GO
CREATE PROCEDURE sp_ProcesarAsistencia
    @ValorDocumento     VARCHAR(30),
    @FechaHoraEntrada   DATETIME,
    @FechaHoraSalida    DATETIME,
    @IdUsuarioSistema   INT,
    @IPOrigen           VARCHAR(45) = '127.0.0.1'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
