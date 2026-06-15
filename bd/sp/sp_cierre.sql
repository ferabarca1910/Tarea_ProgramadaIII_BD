-- ============================================================
-- SP_CIERRE
-- ============================================================

USE PlanillaObrera;
GO
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
        DECLARE @IdSemanaPlanilla INT;
        SELECT @IdSemanaPlanilla = IdSemanaPlanilla
        FROM dbo.SemanaPlanilla
        WHERE FechaFin = @FechaJueves AND Cerrada = 0;

        IF @IdSemanaPlanilla IS NULL
        BEGIN
            RAISERROR('No hay semana planilla abierta que cierre el %s.', 16, 1, CONVERT(VARCHAR,@FechaJueves,103));
            ROLLBACK; RETURN;
        END;

        DECLARE @IdMesPlanilla  INT;
        DECLARE @CantidadJueves TINYINT;

        SELECT
            @IdMesPlanilla  = sp.IdMesPlanilla,
            @CantidadJueves = mp.CantidadJueves
        FROM dbo.SemanaPlanilla sp
        INNER JOIN dbo.MesPlanilla mp ON sp.IdMesPlanilla = mp.IdMesPlanilla
        WHERE sp.IdSemanaPlanilla = @IdSemanaPlanilla;

        DECLARE @IdEmpleado             INT;
        DECLARE @IdPlanillaSemXEmpleado INT;
        DECLARE @SalarioBruto           DECIMAL(14,2);
        DECLARE @TotalDeducciones       DECIMAL(14,2);

        DECLARE cur_empleados CURSOR LOCAL FAST_FORWARD FOR
            SELECT pse.IdPlanillaSemXEmpleado, pse.IdEmpleado, pse.SalarioBruto
            FROM dbo.PlanillaSemXEmpleado pse
            WHERE pse.IdSemanaPlanilla = @IdSemanaPlanilla
              AND pse.Procesada = 0;

        OPEN cur_empleados;
        FETCH NEXT FROM cur_empleados INTO @IdPlanillaSemXEmpleado, @IdEmpleado, @SalarioBruto;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @TotalDeducciones = 0;

            
            DECLARE @IdPlanillaMesXEmpleado INT;
            SELECT @IdPlanillaMesXEmpleado = IdPlanillaMesXEmpleado
            FROM dbo.PlanillaMesXEmpleado
            WHERE IdMesPlanilla = @IdMesPlanilla AND IdEmpleado = @IdEmpleado;
            
            DECLARE @IdTipoDedPct   INT;
            DECLARE @PorcentajeDed  DECIMAL(10,4);
            DECLARE @MontoDed       DECIMAL(12,2);
            DECLARE @IdTipoMovDed   INT;

            DECLARE cur_pct CURSOR LOCAL FAST_FORWARD FOR
                SELECT de.IdTipoDeduccion, td.Valor
                FROM dbo.DeduccionEmpleado de
                INNER JOIN dbo.TipoDeduccion td ON de.IdTipoDeduccion = td.IdTipoDeduccion
                WHERE de.IdEmpleado       = @IdEmpleado
                  AND td.Porcentual       = 1
                  AND de.FechaInicio     <= @FechaJueves
                  AND (de.FechaFin IS NULL OR de.FechaFin >= @FechaJueves);

            OPEN cur_pct;
            FETCH NEXT FROM cur_pct INTO @IdTipoDedPct, @PorcentajeDed;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @MontoDed = ROUND(@SalarioBruto * @PorcentajeDed, 2);
                SET @TotalDeducciones = @TotalDeducciones + @MontoDed;

                INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
                VALUES (@IdPlanillaSemXEmpleado, @IdTipoDedPct + 3, NULL, @FechaJueves, 0, -@MontoDed);

                
                IF @IdPlanillaMesXEmpleado IS NOT NULL
                BEGIN
                    IF EXISTS (SELECT 1 FROM dbo.DeduccionXEmpleadoXMes WHERE IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado AND IdTipoDeduccion = @IdTipoDedPct)
                        UPDATE dbo.DeduccionXEmpleadoXMes
                        SET MontoTotal = MontoTotal + @MontoDed
                        WHERE IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado AND IdTipoDeduccion = @IdTipoDedPct;
                    ELSE
                        INSERT INTO dbo.DeduccionXEmpleadoXMes (IdPlanillaMesXEmpleado, IdTipoDeduccion, MontoTotal)
                        VALUES (@IdPlanillaMesXEmpleado, @IdTipoDedPct, @MontoDed);
                END;

                FETCH NEXT FROM cur_pct INTO @IdTipoDedPct, @PorcentajeDed;
            END;
            CLOSE cur_pct; DEALLOCATE cur_pct;
        
            DECLARE @IdTipoDedFija  INT;
            DECLARE @MontoFijo      DECIMAL(12,2);
            DECLARE @MontoSemanal   DECIMAL(12,2);

            DECLARE cur_fija CURSOR LOCAL FAST_FORWARD FOR
                SELECT de.IdTipoDeduccion, de.MontoFijo
                FROM dbo.DeduccionEmpleado de
                INNER JOIN dbo.TipoDeduccion td ON de.IdTipoDeduccion = td.IdTipoDeduccion
                WHERE de.IdEmpleado       = @IdEmpleado
                  AND td.Porcentual       = 0
                  AND de.MontoFijo        > 0
                  AND de.FechaInicio     <= @FechaJueves
                  AND (de.FechaFin IS NULL OR de.FechaFin >= @FechaJueves);

            OPEN cur_fija;
            FETCH NEXT FROM cur_fija INTO @IdTipoDedFija, @MontoFijo;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @MontoSemanal = ROUND(@MontoFijo / @CantidadJueves, 2);
                SET @TotalDeducciones = @TotalDeducciones + @MontoSemanal;

                INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
                VALUES (@IdPlanillaSemXEmpleado, @IdTipoDedFija + 3, NULL, @FechaJueves, 0, -@MontoSemanal);

                IF @IdPlanillaMesXEmpleado IS NOT NULL
                BEGIN
                    IF EXISTS (SELECT 1 FROM dbo.DeduccionXEmpleadoXMes WHERE IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado AND IdTipoDeduccion = @IdTipoDedFija)
                        UPDATE dbo.DeduccionXEmpleadoXMes
                        SET MontoTotal = MontoTotal + @MontoSemanal
                        WHERE IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado AND IdTipoDeduccion = @IdTipoDedFija;
                    ELSE
                        INSERT INTO dbo.DeduccionXEmpleadoXMes (IdPlanillaMesXEmpleado, IdTipoDeduccion, MontoTotal)
                        VALUES (@IdPlanillaMesXEmpleado, @IdTipoDedFija, @MontoSemanal);
                END;

                FETCH NEXT FROM cur_fija INTO @IdTipoDedFija, @MontoFijo;
            END;
            CLOSE cur_fija; DEALLOCATE cur_fija;
           
            UPDATE dbo.PlanillaSemXEmpleado
            SET
                TotalDeducciones = @TotalDeducciones,
                SalarioNeto      = SalarioBruto - @TotalDeducciones,
                Procesada        = 1
            WHERE IdPlanillaSemXEmpleado = @IdPlanillaSemXEmpleado;

            IF @IdPlanillaMesXEmpleado IS NOT NULL
            BEGIN
                UPDATE dbo.PlanillaMesXEmpleado
                SET
                    SalarioBrutoMensual     = SalarioBrutoMensual     + @SalarioBruto,
                    TotalDeduccionesMensual = TotalDeduccionesMensual + @TotalDeducciones,
                    SalarioNetoMensual      = SalarioNetoMensual      + (@SalarioBruto - @TotalDeducciones)
                WHERE IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado;
            END;

            FETCH NEXT FROM cur_empleados INTO @IdPlanillaSemXEmpleado, @IdEmpleado, @SalarioBruto;
        END;
        CLOSE cur_empleados; DEALLOCATE cur_empleados;
        
        UPDATE dbo.SemanaPlanilla SET Cerrada = 1 WHERE IdSemanaPlanilla = @IdSemanaPlanilla;

        COMMIT TRANSACTION;
        PRINT 'Cierre semanal del ' + CONVERT(VARCHAR,@FechaJueves,103) + ' completado.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg VARCHAR(500) = ERROR_MESSAGE();
        RAISERROR('Error en sp_CierreSemanal: %s', 16, 1, @msg);
    END CATCH;
END;
GO
-- ============================================================
-- SP: AperturaSemana
-- ============================================================
IF OBJECT_ID('sp_AperturaSemana', 'P') IS NOT NULL DROP PROCEDURE sp_AperturaSemana;
GO
CREATE PROCEDURE sp_AperturaSemana
    @FechaInicioSemana  DATE,   -- Viernes siguiente
    @FechaFinSemana     DATE    -- Jueves de la semana nueva
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @IdMesPlanilla INT;
        SELECT @IdMesPlanilla = IdMesPlanilla
        FROM dbo.MesPlanilla
        WHERE FechaInicio <= @FechaInicioSemana
          AND FechaFin    >= @FechaFinSemana
          AND Cerrado = 0;

        IF @IdMesPlanilla IS NULL
        BEGIN
            RAISERROR('No hay mes planilla abierto para la semana %s - %s.',
                16, 1, CONVERT(VARCHAR,@FechaInicioSemana,103), CONVERT(VARCHAR,@FechaFinSemana,103));
            ROLLBACK; RETURN;
        END;


        DECLARE @IdSemanaPlanilla INT;
        INSERT INTO dbo.SemanaPlanilla (IdMesPlanilla, FechaInicio, FechaFin, Cerrada)
        VALUES (@IdMesPlanilla, @FechaInicioSemana, @FechaFinSemana, 0);
        SET @IdSemanaPlanilla = SCOPE_IDENTITY();


        INSERT INTO dbo.PlanillaSemXEmpleado (IdSemanaPlanilla, IdEmpleado, SalarioBruto, TotalDeducciones, SalarioNeto, HorasOrdinarias, HorasExtraNormales, HorasExtraDobles, Procesada)
        SELECT @IdSemanaPlanilla, IdEmpleado, 0, 0, 0, 0, 0, 0, 0
        FROM dbo.Empleado WHERE Activo = 1;

        COMMIT TRANSACTION;
        PRINT 'Apertura de semana planilla completada. IdSemanaPlanilla=' + CAST(@IdSemanaPlanilla AS VARCHAR);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg VARCHAR(500) = ERROR_MESSAGE();
        RAISERROR('Error en sp_AperturaSemana: %s', 16, 1, @msg);
    END CATCH;
END;
GO
-- ============================================================
-- SP: Calcular y registrar aguinaldo 
-- ============================================================
IF OBJECT_ID('sp_CalcularAguinaldo', 'P') IS NOT NULL DROP PROCEDURE sp_CalcularAguinaldo;
GO
CREATE PROCEDURE sp_CalcularAguinaldo
    @Anio               INT,    -- año del aguinaldo (período dic año-1 a nov año)
    @FechaPago          DATE
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;


        DECLARE @FechaInicioPeríodo DATE = CAST(CAST(@Anio-1 AS VARCHAR) + '-12-01' AS DATE);
        DECLARE @FechaFinPeríodo    DATE = CAST(CAST(@Anio   AS VARCHAR) + '-11-30' AS DATE);

        INSERT INTO dbo.Aguinaldo (IdEmpleado, Anio, MontoAguinaldo, FechaPago)
        SELECT
            pme.IdEmpleado,
            @Anio,
            ROUND(SUM(pme.SalarioBrutoMensual) / 12.0, 2),
            @FechaPago
        FROM dbo.PlanillaMesXEmpleado pme
        INNER JOIN dbo.MesPlanilla mp ON pme.IdMesPlanilla = mp.IdMesPlanilla
        WHERE mp.FechaInicio >= @FechaInicioPeríodo
          AND mp.FechaFin    <= @FechaFinPeríodo
        GROUP BY pme.IdEmpleado
        HAVING NOT EXISTS (SELECT 1 FROM dbo.Aguinaldo ag WHERE ag.IdEmpleado = pme.IdEmpleado AND ag.Anio = @Anio);

        COMMIT TRANSACTION;
        PRINT 'dbo.Aguinaldo ' + CAST(@Anio AS VARCHAR) + ' calculado.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg VARCHAR(500) = ERROR_MESSAGE();
        RAISERROR('Error en sp_CalcularAguinaldo: %s', 16, 1, @msg);
    END CATCH;
END;
GO

PRINT 'SPs de cierre, apertura y aguinaldo creados exitosamente.';
GO
