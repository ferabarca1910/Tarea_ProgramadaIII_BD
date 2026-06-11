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
