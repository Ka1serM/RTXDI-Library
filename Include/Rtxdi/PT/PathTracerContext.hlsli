/*
 * SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 * SPDX-License-Identifier: LicenseRef-NvidiaProprietary
 *
 * NVIDIA CORPORATION, its affiliates and licensors retain all intellectual
 * property and proprietary rights in and to this material, related
 * documentation and any modifications thereto. Any use, reproduction,
 * disclosure or distribution of this material and related documentation
 * without an express license agreement from NVIDIA CORPORATION or
 * its affiliates is strictly prohibited.
 */

#if !defined(RTXDI_PT_PATH_TRACING_CONTEXT_HLSLI) || (defined(RTXDI_SLANG) && defined(RTXDI_PT_CONTEXT_NAME))
#ifndef RTXDI_PT_PATH_TRACING_CONTEXT_HLSLI
#define RTXDI_PT_PATH_TRACING_CONTEXT_HLSLI
#endif

#include "Rtxdi/DI/Reservoir.hlsli"
#include "Rtxdi/PT/PathTracerContextParameters.hlsli"
#include "Rtxdi/Utils/BrdfRaySample.hlsli"
#include "Rtxdi/Utils/Math.hlsli"
#include "Rtxdi/Utils/SampledLightData.hlsli"

//
// Principal interface between the path tracer and ReSTIR PT
// Responsible for recording information about the path and
//    the reconnectibility of vertices along it.
//
// Functions are laid out in the order they are called from
//    the path tracing loop
//

#if defined(RTXDI_SLANG)
#define RTXDI_PT_CONTEXT_VALUE_TYPE RTXDI_PT_CONTEXT_NAME
#define RTXDI_PT_CONTEXT_INNER_TYPE RTXDI_PT_CONTEXT_TYPE
#define RTXDI_PT_CONTEXT_INIT_FUNCTION RTXDI_PT_CONTEXT_INIT
#else
#define RTXDI_PT_CONTEXT_NAME RTXDI_PathTracerContext
#define RTXDI_PT_CONTEXT_VALUE_TYPE RTXDI_PathTracerContext<PTContextType>
#define RTXDI_PT_CONTEXT_INNER_TYPE PTContextType
#define RTXDI_PT_CONTEXT_INIT_FUNCTION RTXDI_InitializePathTracerContext
template<typename PTContextType>
#endif
struct RTXDI_PT_CONTEXT_NAME
{
    //
    // The RTXDI_BrdfRaySample contains all the information about
    // the outgoing ray from surface N to surface N+1
    //
    RTXDI_MUTATING void SetBrdfRaySample(RTXDI_BrdfRaySample brs)
    {
        ctx.SetBrdfRaySample(brs);
    }

    RTXDI_MUTATING void SetMaxPathBounce(uint16_t newMax)
    {
        ctx.SetMaxPathBounce(newMax);
    }

    //
    // Updates the maximum reconnection vertex length only if
    // the path so far has not produced a reconnection vertex
    // Thus, if an RC vertex has already been found, this function
    // does nothing. But if an RC vertex has not yet been found,
    // the maximum allowable RC vertex length will be set to the
    // newMax passed in.
    //
    // Useful for selectively increasing the rc vertex length
    // for mirror bounces.
    //
    RTXDI_MUTATING void SetMaxRcVertexLengthIfUnset(uint16_t newMax)
    {
        ctx.SetMaxRcVertexLengthIfUnset(newMax);
    }

    //
    // Enabled for initial sampling
    // Disabled for hybrid shift
    //
    bool ShouldRunRussianRoulette()
    {
        return ctx.ShouldRunRussianRoulette();
    }

    //
    // The context needs to know about the Russian roulette
    // continuation probability to keep resampling unbiased
    //
    RTXDI_MUTATING void RecordRussianRouletteProbability(float rrProb)
    {
        ctx.RecordRussianRouletteProbability(rrProb);
    }

    //
    // Multiplies the path throughput by the given multiplication factor
    //
    // Call after CalculateBRDFOverPDF with the appropriate result
    //
    RTXDI_MUTATING void MultiplyPathThroughput(float3 multiplicationFactor)
    {
        ctx.MultiplyPathThroughput(multiplicationFactor);
    }

    //
    // Sets the outgoing ray direction for the path tracer from the
    //     current surface.
    //
    RTXDI_MUTATING void SetContinuationRay(RayDesc continuationRay)
    {
        ctx.SetContinuationRay(continuationRay);
    }

    //
    // Determines reconnectibility state for the vertex from which the
    //     outgoing ray is departing based off of the ray footprint,
    //     bounce depth, and other reconnectibility state
    //
    // Call after the ray from the surface has been created and before it
    //     is actually traced with RAB_TraceNextBounce
    //
    // Returns true if the path is valid and RAB_TraceNextBounce should
    //     be called.
    // Returns fails if the path is invalid and the path tracer should
    //     exit.
    //
    RTXDI_MUTATING bool AnalyzePathReconnectibilityBeforeTrace()
    {
        return ctx.AnalyzePathReconnectibilityBeforeTrace();
    }

    //
    // Call after AnalyzePathReconnectibilityBeforeTrace
    //
    RTXDI_MUTATING void SetTraceResult(RAB_RayPayload rp)
    {
        ctx.SetTraceResult(rp);
    }

    //
    // Updates the current intersection surface tracked by the context
    //
    // Call this function when the ray traced from surface N hits surface N + 1
    // Do not call this function when the ray misses
    //
    RTXDI_MUTATING void RecordPathIntersection(const RAB_Surface intersectionSurface)
    {
        ctx.RecordPathIntersection(intersectionSurface);
    }

    //
    // The path tracer can use MIS to balance between sampling lights directly via
    //     NEE or casting BRDF rays towards emissive surfaces.
    // Returns true when the context is set to EMISSIVE_ONLY or MIS mode and signals
    //     that the emissive component of intersection surfaces should be sampled
    // Returns false when the context is set to EMISSIVE_ONLY or during hybrid shift
    //
    bool ShouldSampleEmissiveSurfaces()
    {
        return ctx.ShouldSampleEmissiveSurfaces();
    }

    //
    // Records an emissive light sample
    // Assumes the emissive surface is the intersection surface called by
    //     RecordPathIntersection() for tracking reconnection data.
    // Call after RecordPathIntersection()
    //
    RTXDI_MUTATING bool RecordEmissiveLightSample(float3 radianceFromEmissiveSurface, RAB_Surface prevSurface, inout RTXDI_RandomSamplerState rng)
    {
        return ctx.RecordEmissiveLightSample(radianceFromEmissiveSurface, prevSurface, rng);
    }

    //
    // The path tracer can use MIS to balance between sampling lights directly via
    //     NEE or casting BRDF rays towards emissive surfaces.
    // Returns true when the context is set to NEE_ONLY or MIS mode and signals that
    //     lights should be sampled via NEE.
    // Returns false when the context is set to EMISSIVE_ONLY or during hybrid shift
    //
    bool ShouldSampleNee()
    {
        return ctx.ShouldSampleNee();
    }

    //
    // Call after RecordPathIntersection with the results of the path tracer's NEE routine
    //
    RTXDI_MUTATING bool RecordNeeLightSample(in const RTXDI_SampledLightData sampledLightData,
                              in const float3 radianceFromLights,
                              in const float neePdf,
                              in const float scatterPdf,
                              in const RAB_LightSample lightSample,
                              inout RTXDI_RandomSamplerState rng)
    {
        return ctx.RecordNeeLightSample(sampledLightData, radianceFromLights, neePdf, scatterPdf, lightSample, rng);
    }

    RTXDI_MUTATING void RecordPathRadianceMiss(inout RTXDI_RandomSamplerState rng)
    {
        ctx.RecordPathRadianceMiss(rng);
    }

    RTXDI_MUTATING bool RecordEnvironmentMapLightSample(const float3 environmentMapRadiance,
                                         RAB_Surface prevSurface,
                                         inout RTXDI_RandomSamplerState rng)
    {
        return ctx.RecordEnvironmentMapLightSample(environmentMapRadiance, prevSurface, rng);
    }

    float CalculateRISWeight(float3 targetFunctionOverP)
    {
        return ctx.CalculateRISWeight(targetFunctionOverP);
    }

    RTXDI_MUTATING bool RISStreamPathSample(uint pathLength,
                             float3 currentLightRadiance,
                             inout RTXDI_RandomSamplerState rng,
                             uint rcVertexLength,
                             bool isNee,
                             float neePdf,
                             float3 packedLightData,
                             float partialJacobian)
    {
        return ctx.RISStreamPathSample(pathLength, currentLightRadiance, rng, rcVertexLength, isNee, neePdf, packedLightData, partialJacobian);
    }

    bool IsPathTerminated()
    {
        return ctx.IsPathTerminated();
    }

    //
    // PTState functions
    //

    uint GetBounceDepth()
    {
        return ctx.GetBounceDepth();
    }

    uint GetMaxPathBounce()
    {
        return ctx.GetMaxPathBounce();
    }

    RTXDI_BrdfRaySample GetBrdfRaySample()
    {
        return ctx.GetBrdfRaySample();
    }

    RAB_Surface GetIntersectionSurface()
    {
        return ctx.GetIntersectionSurface();
    }

    float3 GetContinuationRayBrdfOverPdf()
    {
        return ctx.GetContinuationRayBrdfOverPdf();
    }

    RayDesc GetContinuationRay()
    {
        return ctx.GetContinuationRay();
    }

    float3 GetPathThroughput()
    {
        return ctx.GetPathThroughput();
    }

    RAB_RayPayload GetTraceResult()
    {
        return ctx.GetTraceResult();
    }

    RTXDI_MUTATING void IncreaseBounceDepth()
    {
        ctx.IncreaseBounceDepth();
    }

    bool ValidContinuationRayBrdfOverPdf()
    {
        return ctx.ValidContinuationRayBrdfOverPdf();
    }

    uint16_t GetRcVertexLength()
    {
        return ctx.GetRcVertexLength();
    }

    //
    // Internal functions
    //

    //
    // Must be called by runtime before sending to RAB_PathTrace
    //
    RTXDI_MUTATING void Init(RTXDI_PathTracerContextParameters ptParams, const RAB_Surface primarySurface, inout RTXDI_PathTracerRandomContext ptRandContext)
    {
        ctx.Init(ptParams, primarySurface, ptRandContext);
    }

    float3 GetRadiance()
    {
        return ctx.GetRadiance();
    }

    float GetRunningWeightSum()
    {
        return ctx.runningWeightSum;
    }

    float GetSelectedPartialJacobian()
    {
        return ctx.selectedPartialJacobian;
    }

    uint GetSelectedPathLength()
    {
        return ctx.selectedPathLength;
    }

    RAB_Surface GetSelectedRcSurface()
    {
        return ctx.selectedRcSurface;
    }

    uint GetSelectedRcVertexLength()
    {
        return ctx.selectedRcVertexLength;
    }

    float GetSelectedRcWiPdf()
    {
        return ctx.selectedRcWiPdf;
    }

    float3 GetSelectedTargetFunction()
    {
        return ctx.GetSelectedTargetFunction();
    }

    //
    // Reconnection Parameters
    //

    RTXDI_PTReconnectionMode GetReconnectionMode()
    {
        return ctx.GetReconnectionMode();
    }

    // Fixed cutoff mode reconnection thrsholds
    float GetRoughnessThreshold()
    {
        return ctx.GetRoughnessThreshold();
    }

    float GetDistanceThreshold()
    {
        return ctx.GetDistanceThreshold();
    }

    // Footprint mode reconnection thresholds
    float GetFootprintThreshold()
    {
        return ctx.GetFootprintThreshold();
    }

    float GetPdfThreshold()
    {
        return ctx.GetPdfThreshold();
    }

    //
    // Hybrid-Shift only functions
    //

    float GetCheckPreRcInverseGeoTerm()
    {
        return ctx.GetCheckPreRcInverseGeoTerm();
    }

    RAB_Surface GetRcPrevSurface()
    {
        return ctx.GetRcPrevSurface();
    }

    RTXDI_MUTATING void SetRcVertexLength(uint length)
    {
        ctx.SetRcVertexLength(length);
    }

    RTXDI_MUTATING void SetSelectedPathLength(uint length)
    {
        ctx.SetSelectedPathLength(length);
    }

    //
    // PTState functions
    //

    bool IsSecondaryBounce()
    {
        return ctx.IsSecondaryBounce();
    }

    // Reset partial state for the next path
    RTXDI_MUTATING void BeginPathState()
    {
        ctx.BeginPathState();
    }

    // Hybrid shift functions

    RTXDI_MUTATING void SetPathTermination(bool value)
    {
        ctx.SetPathTermination(value);
    }

    bool IsPathTermination()
    {
        return ctx.IsPathTermination();
    }

    // PT Base Functions

    RTXDI_MUTATING void SetIsLastVertexFar(bool value)
    {
        ctx.SetIsLastVertexFar(value);
    }

    bool IsLastVertexFar()
    {
        return ctx.IsLastVertexFar();
    }

    RTXDI_MUTATING void SetIsLastVertexRough(bool value)
    {
        ctx.SetIsLastVertexRough(value);
    }

    bool IsLastVertexRough()
    {
        return ctx.IsLastVertexRough();
    }

    bool NoMainPathRcVertex()
    {
        return ctx.NoMainPathRcVertex();
    }

    RTXDI_PT_CONTEXT_INNER_TYPE ctx;
};

#if !defined(RTXDI_SLANG)
template<typename PTContextType>
#endif
RTXDI_PT_CONTEXT_VALUE_TYPE RTXDI_PT_CONTEXT_INIT_FUNCTION(RTXDI_PathTracerContextParameters ptParams, const RAB_Surface primarySurface, inout RTXDI_PathTracerRandomContext ptRandContext)
{
    RTXDI_PT_CONTEXT_VALUE_TYPE ctx = (RTXDI_PT_CONTEXT_VALUE_TYPE)0;
    ctx.ctx.Init(ptParams, primarySurface, ptRandContext);
    return ctx;
}

#undef RTXDI_PT_CONTEXT_VALUE_TYPE
#undef RTXDI_PT_CONTEXT_INNER_TYPE
#undef RTXDI_PT_CONTEXT_INIT_FUNCTION
#if !defined(RTXDI_SLANG)
#undef RTXDI_PT_CONTEXT_NAME
#endif
#endif // RTXDI_PT_PATH_TRACING_CONTEXT_HLSLI
