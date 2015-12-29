/**
 * \file flowfilter.cu
 * \brief Optical flow filter classes.
 * \copyright 2015, Juan David Adarve, ANU. See AUTHORS for more details
 * \license 3-clause BSD, see LICENSE for more details
 */


#include <iostream>
#include <exception>
#include <cmath>

#include "flowfilter/gpu/util.h"
#include "flowfilter/gpu/error.h"
#include "flowfilter/gpu/flowfilter.h"

namespace flowfilter {
namespace gpu {


FlowFilter::FlowFilter() :
    Stage() {

    __height = 0;
    __width = 0;
    __configured = false;
}

FlowFilter::FlowFilter(const int height, const int width) :
    FlowFilter(height, width, 1, 1.0, 1.0) {
        
}

FlowFilter::FlowFilter(const int height, const int width,
        const int smoothIterations,
        const float maxflow,
        const float gamma) :
    Stage() {

    if(height <= 0) {
        std::cerr << "ERROR: FlowFilter::FlowFilter(): height should be greater than zero: "
            << height << std::endl;
        throw std::exception();
    }

    if(width <= 0) {
        std::cerr << "ERROR: FlowFilter::FlowFilter(): width should be greater than zero: "
            << width << std::endl;
        throw std::exception();
    }

    __height = height;
    __width = width;
    __configured = false;

    configure();
    setGamma(gamma);
    setMaxFlow(maxflow);
    setSmoothIterations(smoothIterations);
}

FlowFilter::~FlowFilter() {
    // nothing to do
}


void FlowFilter::configure() {

    // connect the blocks
    __inputImage = GPUImage(__height, __width, 1, sizeof(unsigned char));
    __imageModel = ImageModel(__inputImage);

    // dummy flow field use to instanciate the update block
    // This is necessary to break the circular dependency
    // between propagation and update blocks.
    GPUImage dummyFlow(__height, __width, 2, sizeof(float));

    // FIXME: find good default values
    __update = FlowUpdate(dummyFlow,
        __imageModel.getImageConstant(),
        __imageModel.getImageGradient(),
        1.0, 1.0);

    __smoother = FlowSmoother(__update.getUpdatedFlow(), 1);

    __propagator = FlowPropagator(__smoother.getSmoothedFlow(), 1);

    // set the input flow of the update block to the output
    // of the propagator. This replaces dummyFlow previously
    // assigned to the update
    __update.setInputFlow(__propagator.getPropagatedFlow());
    
    // clear buffers
    __propagator.getPropagatedFlow().clear();
    __update.getUpdatedFlow().clear();
    __update.getUpdatedImage().clear();
    __smoother.getSmoothedFlow().clear();

    __configured = true;
    __firstLoad = true;
}


void FlowFilter::compute() {

    startTiming();

    // compute image model
    __imageModel.compute();

    // propagate old flow
    __propagator.compute();

    // update
    __update.compute();
    
    // smooth updated flow
    __smoother.compute();

    stopTiming();
}

void FlowFilter::loadImage(flowfilter::image_t& image) {
    __inputImage.upload(image);

    if(__firstLoad) {

        std::cout << "FlowFilter::loadImage(): fisrt load" << std::endl;

        // compute image model parameters
        __imageModel.compute();

        // set the old image value to current
        // computed constant brightness parameter
        GPUImage imConstant = __imageModel.getImageConstant();
        __update.getUpdatedImage().copyFrom(imConstant);
        
        __firstLoad = false;
    }
}

void FlowFilter::downloadFlow(flowfilter::image_t& flow) {
    __smoother.getSmoothedFlow().download(flow);
}

void FlowFilter::downloadImage(flowfilter::image_t& image) {
    __update.getUpdatedImage().download(image);
}

// void FlowFilter::downloadImageGradient(flowfilter::image_t& gradient) {
//     __imageModel.getImageGradient().download(gradient);
// }

// void FlowFilter::downloadImageConstant(flowfilter::image_t& image) {
//     __imageModel.getImageConstant().download(image);
// }

// void FlowFilter::downloadImageUpdated(flowfilter::image_t& image) {
//     __update.getUpdatedImage().download(image);
// }

// void FlowFilter::downloadFlowUpdated(flowfilter::image_t& flow) {
//     __update.getUpdatedFlow().download(flow);
// }

// void FlowFilter::downloadSmoothedFlow(flowfilter::image_t& flow) {
//     __smoother.getSmoothedFlow().download(flow);
// }

GPUImage FlowFilter::getFlow() {
    return __update.getUpdatedFlow();
}


float FlowFilter::getGamma() const {
    return __update.getGamma();
}


void FlowFilter::setGamma(const float gamma) {
    __update.setGamma(gamma);
}


float FlowFilter::getMaxFlow() const {
    return __update.getMaxFlow();
}


void FlowFilter::setMaxFlow(const float maxflow) {
    __update.setMaxFlow(maxflow);
    __propagator.setIterations(int(ceilf(maxflow)));
}


int FlowFilter::getSmoothIterations() const {
    return __smoother.getIterations();
}


void FlowFilter::setSmoothIterations(const int N) {
    __smoother.setIterations(N);
}


int FlowFilter::getPropagationIterations() const {
    return __propagator.getIterations();
}

int FlowFilter::height() const {
    return __height;
    
}

int FlowFilter::width() const {
    return __width;
}

}; // namespace gpu
}; // namespace flowfilter