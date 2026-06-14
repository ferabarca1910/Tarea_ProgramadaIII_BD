-- ============================================================
-- SP_CIERRE: Cierre semanal, apertura de semana y apertura de mes
-- Se ejecutan cada jueves a medianoche
-- ============================================================

USE PlanillaObrera;
GO

-- ============================================================
-- SP: Cierre semanal - aplica deducciones y calcula salario neto
-- Se llama cada jueves para la semana que TERMINA ese jueves.
-- ============================================================
IF OBJECT_ID('sp_CierreSemanal', 'P') IS NOT NULL DROP PROCEDURE sp_CierreSemanal;
GO
CREATE PROCEDURE sp_CierreSemanal
    @FechaJueves        DATE,           -- Fecha del jueves de cierre
    @IdUsuarioSistema   INT,
    @IPOrigen           VARCHAR(45) = '127.0.0.1'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
