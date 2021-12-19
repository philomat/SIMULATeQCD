//
// Created by Lukas Mazur on 04.01.19.
//

#ifndef PARALLELGPUCODE_STAGGEREDPHASES_HCU
#define PARALLELGPUCODE_STAGGEREDPHASES_HCU

#include "../../define.h"
#include "../../base/indexer/BulkIndexer.h"



struct calcStaggeredPhase {
    inline __host__ __device__ int operator()(const gSiteMu &siteMu) const {

        typedef GIndexer<All> GInd;

        sitexyzt localCoord = siteMu.coord;
        /// I think we don't need to compute global coord here..
        sitexyzt globalCoord = GInd::getLatData().globalPos(localCoord);

        // printf("Is this even used?\n");

        int rest = globalCoord.x % 2;
        if (rest == 1 && siteMu.mu == 1) return -1;

        rest = (globalCoord.x + globalCoord.y) % 2;
        if (rest == 1 && siteMu.mu == 2) return -1;

        rest = (globalCoord.x + globalCoord.y + globalCoord.z) % 2;
        if (rest == 1 && siteMu.mu == 3) return -1;


        return 1;
    }
};

/*! For fermi statistics we want anti-periodic boundary conditions in the time-direction
 *
 */
struct calcStaggeredBoundary {
    inline __host__ __device__ int operator()(const gSiteMu &siteMu) const {

        typedef GIndexer<All> GInd;

        sitexyzt localCoord = siteMu.coord;
        sitexyzt globalCoord = GInd::getLatData().globalPos(localCoord);

        if ((globalCoord.t == (int) GInd::getLatData().globLT - 1) && siteMu.mu == 3) return -1;

        return 1;
    }
};

#endif //PARALLELGPUCODE_STAGGEREDPHASES_HCU
