#include "include/CurlShims.h"

CURLcode curl_easy_setopt_long(CURL *curl, CURLoption option, long parameter) {
    return curl_easy_setopt(curl, option, parameter);
}

CURLcode curl_easy_setopt_string(CURL *curl, CURLoption option, const char *parameter) {
    return curl_easy_setopt(curl, option, parameter);
}

CURLcode curl_easy_setopt_pointer(CURL *curl, CURLoption option, void *parameter) {
    return curl_easy_setopt(curl, option, parameter);
}

CURLcode curl_easy_setopt_int64(CURL *curl, CURLoption option, curl_off_t parameter) {
    return curl_easy_setopt(curl, option, parameter);
}

CURLcode curl_easy_setopt_write_callback(CURL *curl, CURLoption option, size_t (*callback)(char *ptr, size_t size, size_t nmemb, void *userdata)) {
    return curl_easy_setopt(curl, option, callback);
}

CURLcode curl_easy_setopt_header_callback(CURL *curl, CURLoption option, size_t (*callback)(char *ptr, size_t size, size_t nmemb, void *userdata)) {
    return curl_easy_setopt(curl, option, callback);
}

CURLcode curl_easy_setopt_progress_callback(CURL *curl, CURLoption option, int (*callback)(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow)) {
    return curl_easy_setopt(curl, option, callback);
}

CURLcode curl_easy_getinfo_double(CURL *curl, CURLINFO info, double *value) {
    return curl_easy_getinfo(curl, info, value);
}

CURLcode curl_easy_getinfo_long(CURL *curl, CURLINFO info, long *value) {
    return curl_easy_getinfo(curl, info, value);
}
